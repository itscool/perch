import Foundation
import Darwin

func runProcessEventTests() throws {
    func check(_ b: Bool, _ message: String) throws { if !b { throw AppError(message: message) } }
    func token(_ pid: UInt32, _ version: UInt32 = 1) -> EventToken { .init(auid: getuid(), euid: getuid(), egid: getgid(), ruid: getuid(), rgid: getgid(), pid: pid, asid: 1, pidversion: version) }
    func process(_ pid: UInt32, _ version: UInt32 = 1) -> EventProcess { .init(token: token(pid,version), path: "/bin/zsh", signingID: nil) }
    func event(_ kind: ProcessEvent.Kind, _ a: EventProcess, _ b: EventProcess) -> ProcessEvent { .init(kind: kind, actor: a, subject: b, sequence: 1, arguments: []) }
    let parent = process(100), child = process(101), grandchild = process(102)
    var graph = EventAncestry()
    graph.targets[parent.token] = "agent"
    try check(graph.consume(event(.fork,parent,child), root: nil, exclude: false) == "agent", "Fork attribution failed")
    _ = graph.consume(event(.exit,parent,parent), root: nil, exclude: false)
    try check(graph.consume(event(.fork,child,grandchild), root: nil, exclude: false) == "agent", "Exited ancestor erased descendants")
    _ = graph.consume(event(.exit,child,child), root: nil, exclude: false)
    try check(graph.targets[grandchild.token] == "agent", "Detached grandchild lost")
    let reused = process(101,2)
    try check(graph.consume(event(.fork,reused,process(103)), root: nil, exclude: false) == nil, "Reused PID inherited target")
    let exec = process(102,2)
    try check(graph.consume(event(.exec,grandchild,exec), root: nil, exclude: false) == "agent" && graph.targets[grandchild.token] == nil, "Exec identity transfer failed")
    _ = graph.consume(event(.fork,exec,process(104)), root: nil, exclude: true)
    try check(graph.consume(event(.fork,process(104),process(105)), root: nil, exclude: false) == nil && graph.excluded.contains(token(105)), "Helper descendant exclusion failed")

    func object(_ pid: Int) -> [String:Any] { ["audit_token": ["pid":pid,"pidversion":1,"auid":501,"euid":501,"ruid":501,"egid":20,"rgid":20,"asid":7], "executable":["path":"/tmp/a\\b\"c☕"], "signing_id":"test"] }
    let data = try JSONSerialization.data(withJSONObject: ["global_seq_num": UInt64(8_000_000_000), "process":object(100), "event":["fork":["child":object(101)]], "unused":["nested":[true,NSNull(),-0.025, "fake \\\"pid\\\":3"]]])
    let parsed = try ProcessEvent.parse(data)
    try check(parsed.subject.token.pid == 101 && parsed.subject.path == "/tmp/a\\b\"c☕" && parsed.sequence == 8_000_000_000, "JSON nesting/escape/integer decoding failed")
    for bad in [Data(data.dropLast()), data + Data(" {}".utf8), Data("{\"a\": [1,]}".utf8), Data("{\"a\": 01}".utf8), Data("{\"a\": \"\\q\"}".utf8), Data((String(repeating: "[", count: 70)+"0"+String(repeating: "]", count: 70)).utf8)] {
        do { _ = try ProcessEvent.parse(bad); throw AppError(message: "Malformed JSON was accepted") } catch is EventJSON.Invalid {} catch is DecodingError {}
    }
    // Real event records contain much more metadata than the small ancestry
    // fixture. Exercise nested ignored fields and unaligned input.
    let metadata: [String: Any] = ["files": (0..<12).map { ["path": "/synthetic/metadata/\($0)", "stat": ["size": 1024, "flags": 0], "tags": ["one", "two", "three"]] }, "flags": [true, false, NSNull()]]
    var detailed = object(100); detailed["ignored_metadata"] = metadata
    var detailedChild = object(101); detailedChild["ignored_metadata"] = metadata
    let detailedData = try JSONSerialization.data(withJSONObject: ["global_seq_num": 41, "process": detailed, "event": ["fork": ["child": detailedChild]], "time": "2026-09-05T00:00:00Z"], options: [.sortedKeys])
    for padding in 0..<512 {
        let shifted = Data(("{\"padding\":\"" + String(repeating: "x", count: padding) + "\",").utf8) + detailedData.dropFirst()
        let result = try ProcessEvent.parse(shifted)
        try check(result.actor.token.pid == 100 && result.subject.token.pid == 101 && result.subject.path == parsed.subject.path && result.sequence == 41 && result.sourceTime == "2026-09-05T00:00:00Z", "Input alignment changed event fields")
    }
    for suffix in [",\"ignored\":[1,]}", ",\"ignored\":{\"x\":tru}}", ",\"global_seq_num\":42}"] {
        let bad = Data(detailedData.dropLast()) + Data(suffix.utf8)
        do { _ = try ProcessEvent.parse(bad); throw AppError(message: "Parser accepted malformed or duplicate fields") } catch is EventJSON.Invalid {}
    }
    var runtime = detailedChild
    runtime["executable"] = ["path": "/usr/local/bin/node"]
    runtime["audit_token"] = ["pid": 102, "pidversion": 2, "auid": getuid(), "euid": getuid(), "ruid": getuid(), "egid": getgid(), "rgid": getgid(), "asid": 7]
    let execution = try ProcessEvent.parse(JSONSerialization.data(withJSONObject: ["global_seq_num": 42, "process": detailed, "event": ["exec": ["target": runtime, "args": ["node", "/synthetic/@openai/codex/bin/codex.js", "quoted\"☕", "fourth", "ignored fifth"]]]]))
    try check(execution.kind == .exec && execution.subject.token.pid == 102 && execution.subject.token.pidversion == 2 && execution.arguments == ["node", "/synthetic/@openai/codex/bin/codex.js", "quoted\"☕", "fourth"], "Exec record lost runtime arguments or audit identity")
    let exited = try ProcessEvent.parse(JSONSerialization.data(withJSONObject: ["global_seq_num": 43, "process": detailed, "event": ["exit": ["stat": 0]]]))
    try check(exited.kind == .exit && exited.subject.token == exited.actor.token && exited.sequence == 43, "Exit record changed identity")
    var manyContainers = detailed
    manyContainers["ignored_metadata"] = (0..<600).map { ["id": $0, "nested": ["number": $0 + 1]] }
    let crowded = try ProcessEvent.parse(JSONSerialization.data(withJSONObject: ["global_seq_num": 44, "process": manyContainers, "event": ["fork": ["child": detailedChild]]]))
    try check(crowded.subject.token.pid == 101 && crowded.sequence == 44, "Many ignored containers changed an event")
    // Escaped keys and UTF-16 surrogate pairs must identify exactly the same
    // fields and executable as literal UTF-8, without decoding temporary Strings.
    let literal = String(decoding: detailedData, as: UTF8.self)
    let escaped = Data(literal.replacingOccurrences(of: "global_seq_num", with: "global_\\u0073eq_num").replacingOccurrences(of: "☕", with: "\\u2615").utf8)
    try escaped.withUnsafeBytes { bytes in
        try BorrowedProcessEvent.withBytes(bytes) { e in
            try check(e.subject.path.equals(parsed.subject.path) && e.subject.path.contains("☕") && e.subject.path.hasPrefix("/tmp/") && e.subject.path.basenameEquals("a\\b\"c☕"), "Borrowed escaped comparisons failed")
            try check(!e.subject.path.equals("wrong") && !e.subject.path.contains("absent") && !e.subject.path.basenameEquals("tmp"), "Borrowed comparison accepted a mismatch")
        }
    }
    let plainProcess: [String: Any] = ["audit_token": ["pid": 400000, "pidversion": 1, "auid": getuid(), "euid": getuid(), "ruid": getuid(), "egid": getgid(), "rgid": getgid(), "asid": 7], "executable": ["path": "/synthetic/🪶/node///"]]
    let emoji = try JSONSerialization.data(withJSONObject: ["global_seq_num": UInt64.max, "process": plainProcess, "event": ["exit": [:]]], options: [.sortedKeys, .withoutEscapingSlashes])
    for input in [emoji, Data(String(decoding: emoji, as: UTF8.self).replacingOccurrences(of: "🪶", with: "\\ud83e\\udeb6").utf8)] {
        try input.withUnsafeBytes { bytes in
            try BorrowedProcessEvent.withBytes(bytes) { e in
                try check(e.sequence == UInt64.max && e.subject.path.equals("/synthetic/🪶/node///") && e.subject.path.basenameEquals("node") && e.subject.path.contains("🪶/"), "Unicode/surrogate/maximum sequence failed")
            }
        }
    }
    let emojiJSON = String(decoding: emoji, as: UTF8.self)
    let invalidRecords = [
        emojiJSON.replacingOccurrences(of: String(UInt64.max), with: "18446744073709551616"),
        emojiJSON.replacingOccurrences(of: "400000", with: "4294967296"),
        emojiJSON.replacingOccurrences(of: "400000", with: "-1"),
        emojiJSON.replacingOccurrences(of: "400000", with: "1.0"),
        emojiJSON.replacingOccurrences(of: "400000", with: "01"),
        emojiJSON.replacingOccurrences(of: "🪶", with: "\\ud800"),
        emojiJSON.replacingOccurrences(of: "🪶", with: "\\udc00"),
        emojiJSON.replacingOccurrences(of: "🪶", with: "\\ud800\\u0041"),
        String(emojiJSON.dropLast()) + ",\"global_\\u0073eq_num\":1}",
        String(emojiJSON.dropLast()) + ",\"unused\":" + String(repeating: "[", count: 64) + "0" + String(repeating: "]", count: 64) + "}"
    ].map { Data($0.utf8) }
    let marker = Data("🪶".utf8)
    var invalidUTF8 = emoji
    if let range = invalidUTF8.range(of: marker) { invalidUTF8.replaceSubrange(range, with: [0xf0, 0x80, 0x80, 0x80]) }
    for bad in invalidRecords + [invalidUTF8] {
        do { _ = try ProcessEvent.parse(bad); throw AppError(message: "Invalid Unicode, numeric identity, duplicate key or depth accepted") } catch is EventJSON.Invalid {}
    }
    for args: Any in [123, ["node", 123]] {
        let bad = try JSONSerialization.data(withJSONObject: ["global_seq_num": 45, "process": detailed, "event": ["exec": ["target": runtime, "args": args]]])
        do { _ = try ProcessEvent.parse(bad); throw AppError(message: "Malformed runtime arguments accepted") } catch is EventJSON.Invalid {}
    }
    // Test the real guardian callback with synthetic identities. It never runs
    // timers, changes configuration, invokes panic or signals any process.
    let guardian = AgentGuardian()
    guardian.config.targets = [.init(id: "synthetic", name: "Synthetic", kind: "executable", match: "/synthetic/agent")]
    var syntheticActor = plainProcess
    syntheticActor["executable"] = ["path": "/synthetic/agent"]
    var syntheticChild = plainProcess
    syntheticChild["audit_token"] = ["pid": 400001, "pidversion": 1, "auid": getuid(), "euid": getuid(), "ruid": getuid(), "egid": getgid(), "rgid": getgid(), "asid": 7]
    let born = try JSONSerialization.data(withJSONObject: ["global_seq_num": 1, "process": syntheticActor, "event": ["fork": ["child": syntheticChild]]])
    let ended = try JSONSerialization.data(withJSONObject: ["global_seq_num": 2, "process": syntheticActor, "event": ["exit": [:]]])
    try born.withUnsafeBytes { try BorrowedProcessEvent.withBytes($0) { e in
        guardian.consumeEvent(e)
        try check(guardian.ancestry.targets[e.subject.token] == "synthetic", "Guardian lost short-lived child attribution")
    } }
    try ended.withUnsafeBytes { try BorrowedProcessEvent.withBytes($0) { e in
        guardian.consumeEvent(e)
        try check(guardian.ancestry.targets[e.actor.token] == nil && !guardian.observedActors.contains(e.actor.token) && guardian.ancestry.targets.values.contains("synthetic"), "Guardian exit cleanup erased surviving descendants")
    } }
    // Snapshot app metadata can identify an actor that was previously unmatched.
    // Its next child uses an unrelated path and must inherit the new attribution.
    let refreshed = AgentGuardian()
    refreshed.config.targets = [.init(id: "synthetic", name: "Synthetic", kind: "app", match: "synthetic.bundle")]
    var unrelatedPathChild = syntheticChild
    unrelatedPathChild["executable"] = ["path": "/bin/zsh"]
    let refreshedBorn = try JSONSerialization.data(withJSONObject: ["global_seq_num": 1, "process": syntheticActor, "event": ["fork": ["child": unrelatedPathChild]]])
    try refreshedBorn.withUnsafeBytes { try BorrowedProcessEvent.withBytes($0) { e in refreshed.consumeEvent(e) } }
    refreshed.eventAppPrefixes["synthetic"] = "/synthetic/"
    refreshed.cacheSnapshotIdentities()
    try refreshedBorn.withUnsafeBytes { try BorrowedProcessEvent.withBytes($0) { e in
        refreshed.consumeEvent(e)
        try check(refreshed.ancestry.targets[e.subject.token] == "synthetic", "Snapshot reconciliation retained a stale actor miss")
    } }
    let stream = ProcessEventStream(path: "/nonexistent-perch-test-pipe")
    var delivered = 0
    stream.handler = { _ in delivered += 1 }
    let line = data + Data([10])
    for byte in line { stream.ingest(Data([byte])) }
    try check(delivered == 1 && stream.pending.isEmpty, "Fragmented JSONL framing failed")
    stream.ingest(line) // Duplicate sequence must degrade, never silently claim full coverage.
    try check(delivered == 2 && stream.coverageGap, "Event loss/sequence reset was not reported")
    stream.disconnect("Test disconnection")
    try check(!stream.healthy && stream.coverageGap, "Disconnection erased coverage gap")
    let previousSession = stream.sessionID
    stream.restartObservation()
    try check(stream.sessionID != previousSession && stream.eventCount == 0 && !stream.coverageGap && !stream.healthy,
              "New observation must discard old readiness and require a fresh proof")
    let bounded = ProcessEventStream(path: "/nonexistent-perch-test-pipe")
    bounded.ingest(Data(repeating: 65, count: 2_000_001))
    try check(bounded.pending.isEmpty && bounded.coverageGap, "Oversized stream was not bounded")
    let malformed = ProcessEventStream(path: "/nonexistent-perch-test-pipe")
    malformed.ingest(Data("not json\n".utf8))
    try check(malformed.coverageGap && !malformed.healthy, "Malformed stream reported healthy")

    // Live identity validation never signals anything. Wrong pidversion must fail.
    var audit = audit_token_t()
    var count = mach_msg_type_number_t(MemoryLayout<audit_token_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &audit) { pointer in pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_AUDIT_TOKEN), $0, &count) } }
    try check(result == KERN_SUCCESS, "Cannot obtain test audit token")
    let a = audit.val
    let own = EventToken(auid:a.0,euid:a.1,egid:a.2,ruid:a.3,rgid:a.4,pid:a.5,asid:a.6,pidversion:a.7)
    try check(own.liveProcess()?.identity.pid == getpid(), "Current audit identity was not verified")
    let wrong = EventToken(auid:a.0,euid:a.1,egid:a.2,ruid:a.3,rgid:a.4,pid:a.5,asid:a.6,pidversion:a.7 &+ 1)
    try check(wrong.liveProcess() == nil, "Stale audit token was accepted")
    let start = Date()
    for _ in 0..<10_000 { _ = try ProcessEvent.parse(data) }
    print("PASS: process event parser, detached ancestry, exec, exclusions and audit-token PID reuse; 10,000 fixture events in \(String(format: "%.3f", Date().timeIntervalSince(start)))s")
    let detailedStart = Date()
    for _ in 0..<10_000 { _ = try ProcessEvent.parse(detailedData) }
    print("PASS: metadata/alignment/validation regression; 10,000 \(detailedData.count)-byte events in \(String(format: "%.3f", Date().timeIntervalSince(detailedStart)))s")
    var checksum: UInt64 = 0
    let borrowedStart = DispatchTime.now().uptimeNanoseconds
    try detailedData.withUnsafeBytes { bytes in
        for _ in 0..<100_000 {
            try BorrowedProcessEvent.withBytes(bytes) { e in
                checksum &+= e.sequence &+ UInt64(e.subject.token.pid)
                if e.subject.path.hasPrefix("/tmp/") { checksum &+= 1 }
            }
        }
    }
    let ns = DispatchTime.now().uptimeNanoseconds - borrowedStart
    try check(checksum == 14_300_000, "Borrowed benchmark changed decoded fields")
    print("PASS: production borrowed parser; 100,000 \(detailedData.count)-byte records in \(String(format: "%.3f", Double(ns) / 1e9))s (\(ns / 100_000) ns/event), fixed result \(MemoryLayout<PerchParsedEvent>.size) bytes")

}
