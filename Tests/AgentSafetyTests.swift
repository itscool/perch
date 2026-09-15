import Foundation
import Darwin

func runAgentSafetyTests() throws {
    func fake(_ pid: Int32, _ parent: Int32, _ start: UInt64 = 1) -> AgentProcess {
        .init(identity: .init(pid: pid, uid: getuid(), seconds: start, microseconds: 0), parent: parent, executable: "/test/process-\(pid)")
    }
    func check(_ condition: Bool, _ message: String) throws { if !condition { throw AppError(message: message) } }
    let codexTarget = AgentTarget.defaults.first { $0.id == "app:codex" }!
    let chatTarget = AgentTarget.defaults.first { $0.id == "app:chatgpt" }!
    try check(codexTarget.matchesApp(bundleID: "com.openai.codex", name: "ChatGPT") && !chatTarget.matchesApp(bundleID: "com.openai.codex", name: "ChatGPT"), "Codex display-name ambiguity was not resolved")
    let root = fake(100, 1), child = fake(101,100), grandchild = fake(102,101), unrelated = fake(200,1), protected = fake(103,100)
    var tracker = AgentTracker()
    tracker.update(processes: [root,child,grandchild,unrelated,protected], roots: [root.identity:"agent"], enabledTargets: ["agent"], excluded: [protected.identity])
    try check(Set(tracker.tracked.keys) == Set([root.identity,child.identity,grandchild.identity]), "Descendant closure/exclusion failed")
    let detached = fake(102,1)
    tracker.update(processes: [detached,unrelated], roots: [:], enabledTargets: ["agent"], excluded: [])
    try check(tracker.tracked[detached.identity] != nil, "Observed detached child was forgotten")
    let reused = fake(102,1,2)
    tracker.update(processes: [reused,unrelated], roots: [:], enabledTargets: ["agent"], excluded: [])
    try check(tracker.tracked.isEmpty, "Reused PID remained targeted")
    tracker.update(processes: [root,child], roots: [root.identity:"agent"], enabledTargets: ["agent"], excluded: [])
    tracker.update(processes: [root,child], roots: [:], enabledTargets: [], excluded: [])
    try check(tracker.tracked.isEmpty, "Unselected target remained tracked")

    let fixture = Process()
    fixture.executableURL = URL(fileURLWithPath: "/bin/zsh")
    fixture.arguments = ["-f", "-c", "/bin/sleep 30 & wait"]
    try fixture.run()
    let peer = Process()
    peer.executableURL = URL(fileURLWithPath: "/bin/sleep")
    peer.arguments = ["30"]
    try peer.run()
    var victims: [AgentProcess] = []
    defer {
        for p in victims { _ = ProcessTable.signal(p, SIGKILL) }
        if fixture.isRunning { fixture.terminate() }
        if peer.isRunning { peer.terminate() }
        fixture.waitUntilExit(); peer.waitUntilExit()
    }
    var liveTracker = AgentTracker()
    for _ in 0..<100 {
        let table = ProcessTable.snapshot()
        if let root = table.first(where: { $0.identity.pid == fixture.processIdentifier }) {
            liveTracker.update(processes: table, roots: [root.identity:"fixture"], enabledTargets: ["fixture"], excluded: [])
            if liveTracker.tracked.count >= 2 { break }
        }
        usleep(10_000)
    }
    victims = liveTracker.tracked.values.map(\.process)
    try check(victims.count >= 2 && !victims.contains(where: { $0.identity.pid == peer.processIdentifier }), "Live shell/child selection failed")
    guard let peerIdentity = ProcessTable.inspect(peer.processIdentifier) else { throw AppError(message: "Test peer missing") }
    let stale = AgentProcess(identity: .init(pid: peerIdentity.identity.pid, uid: getuid(), seconds: peerIdentity.identity.seconds + 1, microseconds: peerIdentity.identity.microseconds), parent: peerIdentity.parent, executable: peerIdentity.executable)
    try check(ProcessTable.signal(stale, SIGKILL) == "skipped: PID reused" && peer.isRunning, "Stale identity was not refused")
    for victim in victims { try check(ProcessTable.signal(victim, SIGSTOP) == "sent", "Fixture freeze failed") }
    for victim in victims { try check(ProcessTable.signal(victim, SIGKILL) == "sent", "Fixture termination failed") }
    for _ in 0..<100 {
        if victims.allSatisfy({ ProcessTable.inspect($0.identity.pid)?.identity != $0.identity }) { break }
        usleep(10_000)
    }
    try check(victims.allSatisfy({ ProcessTable.inspect($0.identity.pid)?.identity != $0.identity }) && peer.isRunning, "Fixture stop verification/unrelated-process preservation failed")
    print("PASS: ancestry, observed detached children, PID reuse, exclusions, removed targets; disposable shell + child frozen/terminated; unrelated process preserved")
}
