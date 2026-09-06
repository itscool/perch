import Foundation
import Darwin
import ServiceManagement

enum CPUDisplaySettings {
    static let key = "showProcessCPU"
    static func enabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) == nil || defaults.bool(forKey: key)
    }
}

struct ProcessCPUCounter {
    let pid: Int32
    let birth: UInt64
    let native: Bool
    let seconds: Double
    let started: Double
}

struct ProcessCPUSnapshot {
    let time: Double
    let counters: [Int32: ProcessCPUCounter]
    let perch: Set<Int32>
    let complete: Bool
    let perchComplete: Bool
}

struct ProcessCPUReading {
    let topPID: Int32?
    let topPercent: Double
    let perchPercent: Double?
    let complete: Bool
    var topIsPerch: Bool { topPID == nil && perchPercent != nil }

    // Every value uses total logical CPU capacity, matching the existing CPU row.
    static func between(_ old: ProcessCPUSnapshot, _ new: ProcessCPUSnapshot, cores: Int) -> Self? {
        let elapsed = new.time - old.time
        guard elapsed > 0, elapsed <= 20, cores > 0 else { return nil }
        var top: (Int32, Double)?
        var ours = 0.0
        var measured = Set<Int32>()
        var complete = new.complete
        for (pid, value) in new.counters {
            let delta: Double
            if let prior = old.counters[pid], prior.birth == value.birth, prior.native == value.native {
                delta = value.seconds - prior.seconds
            } else if value.started >= old.time && value.started <= new.time {
                delta = value.seconds
            } else { complete = false; continue }
            guard delta.isFinite, delta >= 0 else { continue }
            let percent = min(100, 100 * delta / elapsed / Double(cores))
            measured.insert(pid)
            if new.perch.contains(pid) { ours += percent }
            else if top == nil || percent > top!.1 || (percent == top!.1 && pid < top!.0) { top = (pid, percent) }
        }
        let ourPercent: Double? = new.perchComplete && new.perch.isSubset(of: measured) ? min(100, ours) : nil
        guard top != nil || ourPercent != nil else { return nil }
        if let ourPercent, ourPercent >= (top?.1 ?? 0) {
            return Self(topPID: nil, topPercent: ourPercent, perchPercent: ourPercent, complete: complete)
        }
        return Self(topPID: top?.0, topPercent: top?.1 ?? 0, perchPercent: ourPercent, complete: complete)
    }
    static func percent(_ value: Double) -> String {
        if value > 0 && value < 0.005 { return "<0.01%" }
        return String(format: value < 1 ? "%.2f%%" : "%.1f%%", value)
    }
    func text(name: String) -> String {
        let clean = String(name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(String.init).joined().prefix(24))
        let top = (complete ? "top: " : "top observed: ") + (topIsPerch ? "Perch" : (clean.isEmpty ? "Unknown" : clean)) + " " + Self.percent(topPercent)
        return topIsPerch ? top : top + " · us: " + (perchPercent.map(Self.percent) ?? "Unavailable")
    }
}

/// Native counters for readable processes; Apple's ps supplies only the protected
/// subset. No elevated helper, task-port entitlement, command arguments or disk log.
final class ProcessCPUReader {
    private var pids = [Int32](repeating: 0, count: 16_384)
    private let secondsPerTick: Double = {
        var base = mach_timebase_info_data_t(); mach_timebase_info(&base)
        return Double(base.numer) / Double(base.denom) / 1_000_000_000
    }()
    private(set) var lastNativeCount = 0
    private(set) var lastProtectedCount = 0
    private(set) var lastWallMS = 0.0

    func read(perchPIDs: Set<Int32>, helpersKnown: Bool) -> ProcessCPUSnapshot {
        let began = DispatchTime.now().uptimeNanoseconds
        let time = ProcessInfo.processInfo.systemUptime
        let wallTime = Date().timeIntervalSince1970
        let ticks = mach_absolute_time()
        var ours = perchPIDs
        // Deprecated but still the public read-only API for the job's actual PID.
        // This avoids spawning launchctl or counting somebody else's eslogger.
        if let job = SMJobCopyDictionary(kSMDomainSystemLaunchd, "local.scott.perch.events" as CFString)?.takeRetainedValue() as? [String: Any],
           let pid = (job["PID"] as? NSNumber)?.int32Value, pid > 1 { ours.insert(pid) }
        let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size)))
        var complete = count > 0 && count < pids.count
        var counters: [Int32: ProcessCPUCounter] = [:]
        counters.reserveCapacity(max(0, min(count, pids.count)))
        var protected: [Int32: UInt64] = [:]
        for pid in pids.prefix(max(0, min(count, pids.count))) where pid > 0 {
            var usage = rusage_info_v2()
            let result = withUnsafeMutablePointer(to: &usage) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
            }
            if result == 0 {
                // XNU counters are Mach ticks, including on Apple Silicon.
                var cpu = Double(usage.ri_user_time) + Double(usage.ri_system_time)
                // Include completed utilities launched by Perch (including this ps).
                if ours.contains(pid) { cpu += Double(usage.ri_child_user_time) + Double(usage.ri_child_system_time) }
                counters[pid] = ProcessCPUCounter(pid: pid, birth: usage.ri_proc_start_abstime, native: true,
                    seconds: cpu * secondsPerTick, started: time - Double(ticks &- min(ticks, usage.ri_proc_start_abstime)) * secondsPerTick)
            } else if let birth = Self.birth(pid) { protected[pid] = birth }
            else if kill(pid, 0) == 0 || errno == EPERM { complete = false }
        }
        lastNativeCount = counters.count; lastProtectedCount = protected.count
        if !protected.isEmpty {
            let arguments = ["-p", protected.keys.sorted().map(String.init).joined(separator: ","), "-o", "pid=,time="]
            if let output = Self.capture("/bin/ps", arguments), let values = Self.parsePS(output) {
                for (pid, birth) in protected {
                    // Never attach a reused PID's CPU time to its predecessor.
                    if let seconds = values[pid], Self.birth(pid) == birth {
                        counters[pid] = ProcessCPUCounter(pid: pid, birth: birth, native: false, seconds: seconds, started: time - (wallTime - Double(birth) / 1_000_000))
                    } else if Self.birth(pid) == birth { complete = false }
                }
            } else { complete = false }
        }
        lastWallMS = Double(DispatchTime.now().uptimeNanoseconds - began) / 1_000_000
        return ProcessCPUSnapshot(time: time, counters: counters, perch: ours, complete: complete, perchComplete: helpersKnown)
    }
    static func birth(_ pid: Int32) -> UInt64? {
        // KERN_PROC_PID exposes birth identity for other users' processes even
        // where libproc denies PROC_PIDTBSDINFO. No task port is requested.
        var info = kinfo_proc(), size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size == MemoryLayout<kinfo_proc>.size,
              info.kp_proc.p_un.__p_starttime.tv_sec > 0 else { return nil }
        return UInt64(info.kp_proc.p_un.__p_starttime.tv_sec) * 1_000_000 + UInt64(info.kp_proc.p_un.__p_starttime.tv_usec)
    }
    static func name(_ pid: Int32) -> String {
        let path: String? = withUnsafeTemporaryAllocation(of: CChar.self, capacity: 4096) { path in
            guard proc_pidpath(pid, path.baseAddress, UInt32(path.count)) > 0 else { return nil }
            return URL(fileURLWithPath: String(cString: path.baseAddress!)).lastPathComponent
        }
        if let path { return path }
        var info = kinfo_proc(), size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        if sysctl(&mib, 4, &info, &size, nil, 0) == 0, size == MemoryLayout<kinfo_proc>.size {
            let name = withUnsafeBytes(of: info.kp_proc.p_comm) { bytes in
                String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
            }
            if !name.isEmpty { return name }
        }
        return "PID \(pid)"
    }
    static func parsePS(_ output: String) -> [Int32: Double]? {
        var result: [Int32: Double] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count == 2, let pid = Int32(fields[0]), pid > 0, let seconds = duration(String(fields[1])), result[pid] == nil else { return nil }
            result[pid] = seconds
        }
        return result
    }
    static func duration(_ value: String) -> Double? {
        let dayParts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard (1...2).contains(dayParts.count) else { return nil }
        var days = 0.0
        if dayParts.count == 2 {
            guard !dayParts[0].isEmpty, dayParts[0].allSatisfy({ $0.isASCII && $0.isNumber }), let d = Double(dayParts[0]) else { return nil }
            days = d
        }
        let fields = dayParts.last!.split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(fields.count) else { return nil }
        var total = 0.0
        for (index, field) in fields.enumerated() {
            guard !field.isEmpty, field.allSatisfy({ ($0.isASCII && $0.isNumber) || (index == fields.count - 1 && $0 == ".") }),
                  let number = Double(field), number.isFinite, number >= 0,
                  index == 0 || number < 60 else { return nil }
            total = total * 60 + number
        }
        total += days * 86400
        return total.isFinite ? total : nil
    }

    // Only runs on the sampler queue. Bound both the pipe and child lifetime;
    // poll sleeps until output/EOF instead of spinning or blocking AppKit.
    static func capture(_ executable: String, _ arguments: [String]) -> String? {
        let task = Process(), pipe = Pipe(), exited = DispatchSemaphore(value: 0)
        task.executableURL = URL(fileURLWithPath: executable); task.arguments = arguments
        var environment = ProcessInfo.processInfo.environment; environment["LC_ALL"] = "C"; task.environment = environment
        task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
        task.terminationHandler = { _ in exited.signal() }
        do { try task.run() } catch { return nil }
        pipe.fileHandleForWriting.closeFile()
        let fd = pipe.fileHandleForReading.fileDescriptor
        defer { pipe.fileHandleForReading.closeFile() }
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        let deadline = DispatchTime.now().uptimeNanoseconds + 1_000_000_000
        var bytes = Data(), success = false
        withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 8192) { buffer in
            while DispatchTime.now().uptimeNanoseconds < deadline {
                let n = Darwin.read(fd, buffer.baseAddress, buffer.count)
                if n > 0 {
                    guard bytes.count + n <= 524_288 else { break }
                    bytes.append(buffer.baseAddress!, count: n); continue
                }
                if n == 0 { success = true; break }
                if errno == EINTR { continue }
                if errno != EAGAIN { break }
                var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                let current = DispatchTime.now().uptimeNanoseconds
                let remaining = deadline > current ? (deadline - current) / 1_000_000 : 0
                _ = poll(&descriptor, 1, Int32(min(remaining, 1000)))
            }
        }
        let finished = exited.wait(timeout: .now() + .milliseconds(100)) == .success
        if !finished && task.isRunning { kill(task.processIdentifier, SIGKILL) }
        guard success, finished, task.terminationStatus == 0 else { return nil }
        return String(data: bytes, encoding: .utf8)
    }
}

/// Main-thread facade. Uses the menu's existing refresh; no timer, requests or
/// background scan while the menu is closed or the setting is off.
final class ProcessCPUSampler {
    private let queue = DispatchQueue(label: "local.scott.perch.cpu", qos: .utility)
    private let reader = ProcessCPUReader()
    private var previous: ProcessCPUSnapshot? // sampler queue only
    private var active = false
    private var pending = false
    private var generation = 0
    private var nextRead = 0.0
    private(set) var requests = 0
    var onUpdate: (() -> Void)?
    private(set) var text = "top: Measuring… · us: Measuring…"
    func setActive(_ value: Bool) {
        guard active != value else { return }
        active = value; generation += 1; pending = false; nextRead = 0
        text = "top: Measuring… · us: Measuring…"
        queue.async { [self] in previous = nil }
    }
    func refresh(now: Double = ProcessInfo.processInfo.systemUptime) {
        guard active, !pending, now >= nextRead else { return }
        let monitor = HelperStatusIPC.guardianClient.value, input = HelperStatusIPC.inputClient.value
        var pids: Set<Int32> = [getpid()]
        if let monitor, monitor.fresh { pids.insert(monitor.watcherPID) }
        if let input, input.fresh { pids.insert(input.pid) }
        let known = monitor?.fresh == true && input?.fresh == true
        let capturedPIDs = pids, token = generation
        pending = true; nextRead = now + 10; requests += 1
        queue.async { [self] in
            let sample = reader.read(perchPIDs: capturedPIDs, helpersKnown: known)
            let reading = previous.flatMap { ProcessCPUReading.between($0, sample, cores: ProcessInfo.processInfo.processorCount) }
            let first = previous == nil; previous = sample
            let line = reading.map { $0.text(name: $0.topPID.map(ProcessCPUReader.name) ?? "Perch") }
            DispatchQueue.main.async { [self] in
                guard active, generation == token else { return }
                pending = false
                if first { nextRead = now + 1 }
                else { text = line ?? "top: Unavailable · us: Unavailable"; onUpdate?() }
            }
        }
    }
}
