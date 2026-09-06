import Foundation
import Darwin

struct EventToken: Hashable {
    let auid: UInt32, euid: UInt32, egid: UInt32, ruid: UInt32, rgid: UInt32, pid: UInt32, asid: UInt32, pidversion: UInt32
    var audit: audit_token_t { audit_token_t(val: (auid,euid,egid,ruid,rgid,pid,asid,pidversion)) }
    func liveProcess() -> AgentProcess? {
        guard pid > 1, pid <= UInt32(Int32.max), ruid == getuid() else { return nil }
        var token = audit
        return withUnsafeTemporaryAllocation(of: CChar.self, capacity: 4 * Int(MAXPATHLEN)) { path in
            var info = proc_bsdinfo()
            // Audit-token checks bracket the metadata query: PID reuse or exec
            // during inspection invalidates the result. No separate PID-only
            // path query, temporary Array or temporary path String is needed.
            guard proc_pidpath_audittoken(&token, path.baseAddress, UInt32(path.count)) > 0,
                  proc_pidinfo(Int32(pid), PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size,
                  info.pbi_uid == getuid(), info.pbi_status != 5,
                  proc_pidpath_audittoken(&token, path.baseAddress, UInt32(path.count)) > 0 else { return nil }
            return AgentProcess(identity: .init(pid: Int32(pid), uid: info.pbi_uid, seconds: info.pbi_start_tvsec, microseconds: info.pbi_start_tvusec),
                                parent: Int32(info.pbi_ppid), executable: String(cString: path.baseAddress!))
        }
    }
}
struct EventProcess {
    let token: EventToken
    let path: String
    let signingID: String?
}
struct ProcessEvent {
    enum Kind { case fork, exec, exit }
    let kind: Kind
    let actor: EventProcess
    let subject: EventProcess
    let sequence: UInt64
    let arguments: [String]
    var sourceTime: String? = nil
    static func parse(_ data: Data) throws -> ProcessEvent {
        try data.withUnsafeBytes { try BorrowedProcessEvent.withBytes($0) { $0.retained() } }
    }
}

// Live execution identities; ancestry transfers before the exited parent is removed.
// No process-table lookup is needed to attribute short-lived intermediate children.
struct EventAncestry {
    var targets: [EventToken: String] = [:]
    var excluded: Set<EventToken> = []
    mutating func consume(_ e: ProcessEvent, root: String?, exclude: Bool) -> String? {
        consume(kind: e.kind, actor: e.actor.token, subject: e.subject.token, root: root, exclude: exclude)
    }
    mutating func consume(kind: ProcessEvent.Kind, actor: EventToken, subject: EventToken, root: String?, exclude: Bool) -> String? {
        if kind == .exit { targets.removeValue(forKey: actor); excluded.remove(actor); return nil }
        let inherited = targets[actor]
        let protected = exclude || excluded.contains(actor)
        if kind == .exec { targets.removeValue(forKey: actor); excluded.remove(actor) }
        if protected { excluded.insert(subject); return nil }
        if let target = root ?? inherited { targets[subject] = target; return target }
        return nil
    }
}

final class ProcessEventStream {
    static let pipePath = "/Library/Application Support/Perch Events/events.pipe"
    let path: String
    init(path: String = ProcessEventStream.pipePath) { self.path = path }
    deinit { reader?.stop() }
    var sessionID = UUID().uuidString
    var eventCount = 0
    var bytesReceived: UInt64 = 0
    var sampledEvents: UInt64 = 0
    var sampledParseNS: UInt64 = 0
    var sampledHandlerNS: UInt64 = 0
    struct Diagnostics {
        let reader: EventPipeReader.Metrics?
        let samples: UInt64, parseNS: UInt64, handlerNS: UInt64, bytes: UInt64
        let probe: Int32?
        let timestamp: PerchEventTimestamp
        let paths: Set<String>
        let probes: [UInt32: Date]
        var text: String {
            let n = max(1, samples)
            let source: String
            if timestamp.length == 0 { source = "none" }
            else if timestamp.length > 128 { source = "<timestamp exceeds diagnostic limit>" }
            else { source = withUnsafeBytes(of: timestamp.bytes) { String(decoding: $0.prefix(timestamp.length), as: UTF8.self) } }
            return "\(reader?.text ?? "no reader") samples=\(samples) parseUs=\(parseNS / n / 1000) handlerUs=\(handlerNS / n / 1000) bytesReceived=\(bytes) probe=\(probe ?? -1) sourceTime=\(source) matchingPaths=\(paths.sorted()) truePIDs=\(probes.keys.sorted())"
        }
    }
    var diagnosticSnapshot: Diagnostics {
        Diagnostics(reader: reader?.metrics, samples: sampledEvents, parseNS: sampledParseNS,
                    handlerNS: sampledHandlerNS, bytes: bytesReceived, probe: probePID,
                    timestamp: sourceTimestamp, paths: seenProbePaths, probes: recentProbeEvents)
    }
    var pipelineDiagnostics: String {
        let n = max(1, sampledEvents)
        return "\(reader?.diagnostics ?? "no reader") samples=\(sampledEvents) parseUs=\(sampledParseNS / n / 1000) handlerUs=\(sampledHandlerNS / n / 1000)"
    }
    var sourceTimestamp = PerchEventTimestamp()
    var lastSourceTime: String? {
        guard sourceTimestamp.length != 0 else { return nil }
        guard sourceTimestamp.length <= 128 else { return "<timestamp exceeds diagnostic limit>" }
        return withUnsafeBytes(of: sourceTimestamp.bytes) { String(decoding: $0.prefix(sourceTimestamp.length), as: UTF8.self) }
    }
    var seenProbePaths: Set<String> = []
    var lastEvent: Date?
    var reader: EventPipeReader?
    var connectionID = UUID()
    var fd: Int32 = -1
    var pending = Data()
    var handler: ((BorrowedProcessEvent) -> Void)?
    var failure: String? = "Process events need setup. Open Agent safety settings."
    var coverageGap = false
    var lastSequence: UInt64?
    var lastProbe = Date.distantPast
    var probePID: Int32?
    var recentProbeEvents: [UInt32: Date] = [:]
    var lastProof = Date.distantPast
    var nextOpen = Date.distantPast
    var probe: Process?
    var healthy: Bool { failure == nil && Date().timeIntervalSince(lastProof) < 45 }
    func connect() {
        guard fd < 0, Date() >= nextOpen else { return }
        nextOpen = Date().addingTimeInterval(5)
        var info = stat()
        guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFIFO, info.st_uid == getuid(), info.st_mode & 0o077 == 0 else { return }
        fd = open(path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return }
        let id = UUID(); connectionID = id
        reader = EventPipeReader(descriptor: fd, readable: { [weak self] in
            guard let self, self.connectionID == id else { return }; self.drain()
        }, failed: { [weak self] reason in
            guard let self, self.connectionID == id else { return }; self.disconnect(reason)
        })
        lastSequence = nil; pending.removeAll(keepingCapacity: true)
    }
    func disconnect(_ reason: String) {
        if lastSequence != nil { coverageGap = true }
        failure = reason; lastProof = .distantPast
        connectionID = UUID()
        reader?.stop(); reader = nil; fd = -1
        pending.removeAll(keepingCapacity: true); lastSequence = nil
        nextOpen = Date().addingTimeInterval(5)
    }
    func drain() {
        guard fd >= 0, let reader else { return }
        for data in reader.takeAvailable() {
            bytesReceived += UInt64(data.count)
            ingest(data)
            if fd < 0 { return }
        }
    }
    func ingest(_ data: Data) {
        pending.append(data)
        var consumed = pending.startIndex
        func nextNewline() -> Int? {
            pending.withUnsafeBytes { raw in
                let offset = consumed - pending.startIndex
                guard offset < raw.count, let base = raw.baseAddress,
                      let found = memchr(base.advanced(by: offset), 10, raw.count - offset) else { return nil }
                return pending.startIndex + base.distance(to: UnsafeRawPointer(found))
            }
        }
        while let end = nextNewline() {
            let lineCount = end - consumed
            guard lineCount <= 2_000_000 else { coverageGap = true; disconnect("Oversized process event; ancestry coverage has a gap."); return }
            do {
                // Sample one event in 64; avoid timing syscalls on every event.
                let measure = eventCount % 64 == 0
                let start = measure ? DispatchTime.now().uptimeNanoseconds : 0
                let offset = consumed - pending.startIndex
                try pending.withUnsafeBytes { raw in
                    try BorrowedProcessEvent.withBytes(UnsafeRawBufferPointer(rebasing: raw[offset..<(offset + lineCount)])) { event in
                        if measure { sampledParseNS += DispatchTime.now().uptimeNanoseconds - start; sampledEvents += 1 }
                        if let previous = lastSequence, event.sequence != previous &+ 1 { coverageGap = true; failure = "Process events were lost; ancestry coverage has a gap." }
                        lastSequence = event.sequence; eventCount += 1; lastEvent = Date(); perch_timestamp_copy(event.input, event.raw.time, &sourceTimestamp)
                        if Int64(event.subject.token.pid) == Int64(probePID ?? -1) { seenProbePaths.insert(event.subject.path.retainedString()) }
                        if event.subject.path.equals("/usr/bin/true") && event.subject.token.ruid == getuid() {
                            if recentProbeEvents.count > 64 { recentProbeEvents.removeAll(keepingCapacity: true) }
                            recentProbeEvents[event.subject.token.pid] = Date()
                            if Int64(event.subject.token.pid) == Int64(probePID ?? -1) { confirmProbe() }
                        }
                        let handlerStart = measure ? DispatchTime.now().uptimeNanoseconds : 0
                        handler?(event)
                        if measure { sampledHandlerNS += DispatchTime.now().uptimeNanoseconds - handlerStart }
                    }
                }
            } catch { coverageGap = true; failure = "Unrecognized process-event output; ancestry coverage has a gap." }
            consumed = pending.index(after: end)
        }
        if consumed > pending.startIndex { pending.removeSubrange(pending.startIndex..<consumed) }
        if pending.count > 2_000_000 { coverageGap = true; disconnect("Process event exceeded the buffer limit; ancestry coverage has a gap.") }
    }
    func restartObservation() {
        disconnect("Checking the updated process-event collector…")
        coverageGap = false
        sessionID = UUID().uuidString
        eventCount = 0; bytesReceived = 0; lastEvent = nil; sourceTimestamp = PerchEventTimestamp()
        lastProbe = .distantPast; probePID = nil
        recentProbeEvents.removeAll(); seenProbePaths.removeAll()
        nextOpen = .distantPast
    }
    func confirmProbe() {
        lastProof = Date()
        failure = coverageGap ? "Process-event coverage has a gap from earlier interrupted collection." : nil
    }
    func tick() {
        connect()
        // Nonblocking fallback drain also handles FIFO writer reconnection notifications.
        drain()
        if fd >= 0 && Date().timeIntervalSince(lastProbe) >= 30 {
            lastProbe = Date()
            recentProbeEvents.removeAll(keepingCapacity: true)
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/true")
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            p.terminationHandler = { _ in }
            do { try p.run(); probePID = p.processIdentifier; probe = p
                if recentProbeEvents[UInt32(p.processIdentifier)] != nil { confirmProbe() }
            } catch { failure = "Could not check the process-event stream." }
        }
        if probePID != nil && lastProof < lastProbe && Date().timeIntervalSince(lastProbe) > 10 { failure = coverageGap ? "Process-event coverage has a gap. Restart observation to begin a new verified session." : "Process-event health check timed out. The collector is not delivering the probe event." }
    }
}
