import Foundation
import Darwin

func runProcessCPUTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    let suite = "local.scott.perch.cpu-tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    try check(CPUDisplaySettings.enabled(in: defaults), "CPU display must default on")
    defaults.set(false, forKey: CPUDisplaySettings.key)
    try check(!CPUDisplaySettings.enabled(in: defaults), "CPU display ignored explicit off")
    func counter(_ pid: Int32, _ seconds: Double, birth: UInt64 = 1, started: Double = 0) -> ProcessCPUCounter {
        ProcessCPUCounter(pid: pid, birth: birth, native: true, seconds: seconds, started: started)
    }
    func snapshot(_ time: Double, _ rows: [ProcessCPUCounter], complete: Bool = true) -> ProcessCPUSnapshot {
        ProcessCPUSnapshot(time: time, counters: Dictionary(uniqueKeysWithValues: rows.map { ($0.pid, $0) }), perch: [10, 11, 12, 13], complete: complete, perchComplete: true)
    }
    let old = snapshot(10, [counter(10, 1), counter(11, 1), counter(12, 1), counter(13, 1), counter(20, 2)])
    let next = snapshot(20, [counter(10, 1.2), counter(11, 1.3), counter(12, 1.1), counter(13, 1.4), counter(20, 6)])
    let reading = ProcessCPUReading.between(old, next, cores: 4)!
    try check(reading.topPID == 20 && abs(reading.topPercent - 10) < 0.00001 && abs(reading.perchPercent! - 2.5) < 0.00001, "CPU grouping or total-capacity normalization failed")
    try check(reading.text(name: "Test").contains("top: Test 10.0% · us: 2.5%"), "CPU row labels failed")
    let ours = snapshot(20, [counter(10, 2), counter(11, 2), counter(12, 2), counter(13, 3), counter(20, 6)])
    let winner = ProcessCPUReading.between(old, ours, cores: 4)!
    try check(winner.topIsPerch && winner.text(name: "unused") == "top: Perch 12.5%", "Perch winner was not grouped or was duplicated")
    let missing = snapshot(20, [counter(10, 1.2), counter(11, 1.3), counter(12, 1.1), counter(20, 6)], complete: false)
    let partial = ProcessCPUReading.between(old, missing, cores: 4)!
    try check(partial.perchPercent == nil && partial.text(name: "Test").contains("us: Unavailable") && partial.text(name: "Test").hasPrefix("top observed:"), "Missing collector falsely appeared as zero usage")
    let reused = snapshot(20, [counter(10, 1.2), counter(11, 1.3), counter(12, 1.1), counter(13, 1.4), counter(20, 900, birth: 2)])
    try check(ProcessCPUReading.between(old, reused, cores: 4)!.topIsPerch, "Reused PID inherited predecessor's CPU")
    let newborn = snapshot(20, [counter(10, 1.2), counter(11, 1.3), counter(12, 1.1), counter(13, 1.4), counter(30, 4, birth: 3, started: 15)])
    try check(ProcessCPUReading.between(old, newborn, cores: 4)?.topPID == 30, "New process within interval was ignored")
    try check(ProcessCPUReading.between(old, old, cores: 4) == nil && ProcessCPUReading.between(old, snapshot(100, []), cores: 4) == nil, "Stale or empty CPU interval was accepted")
    try check(ProcessCPUReader.duration("123:45.67") == 7425.67 && ProcessCPUReader.duration("01:02:03.00") == 3723 && ProcessCPUReader.duration("2-01:02:03.00") == 176523, "ps CPU time parsing failed")
    for bad in ["", "NaN", "1:60.00", "1::01", "1:1e2", "-1:01", "1:01:01:01", "1:01.2.3"] {
        try check(ProcessCPUReader.duration(bad) == nil, "Invalid ps duration accepted: \(bad)")
    }
    try check(ProcessCPUReader.parsePS(" 12 00:00.01\n13 12:20.00\n")?[13] == 740 && ProcessCPUReader.parsePS("12 1:00\n12 2:00") == nil, "ps rows or duplicate PID validation failed")
    let disabled = ProcessCPUSampler()
    for _ in 0..<100 { disabled.refresh() }
    try check(disabled.requests == 0, "Closed/disabled CPU sampler performed work")
    print("PASS: default-on CPU setting, combined Perch/collector totals, one denominator, top-only Perch, missing readings, PID reuse, new processes, stale intervals, ps parsing and no closed-menu sampling")
}

func runProcessCPUBenchmark() {
    let reader = ProcessCPUReader()
    var selfBefore = rusage(), childrenBefore = rusage(), selfAfter = rusage(), childrenAfter = rusage()
    getrusage(RUSAGE_SELF, &selfBefore); getrusage(RUSAGE_CHILDREN, &childrenBefore)
    var wall = 0.0
    var last: ProcessCPUSnapshot?
    for _ in 0..<20 { last = reader.read(perchPIDs: [getpid()], helpersKnown: false); wall += reader.lastWallMS }
    getrusage(RUSAGE_SELF, &selfAfter); getrusage(RUSAGE_CHILDREN, &childrenAfter)
    func cpu(_ value: rusage) -> Double {
        Double(value.ru_utime.tv_sec + value.ru_stime.tv_sec) + Double(value.ru_utime.tv_usec + value.ru_stime.tv_usec) / 1_000_000
    }
    let own = (cpu(selfAfter) - cpu(selfBefore)) / 20 * 1000
    let child = (cpu(childrenAfter) - cpu(childrenBefore)) / 20 * 1000
    if let last { print("Protected Perch collector included:", last.perch.subtracting([getpid()]).allSatisfy { last.counters[$0] != nil }, "; collector count:", last.perch.count - 1, "; all enumerated live processes readable:", last.complete) }
    print(String(format: "CPU sampling: native=%d protected=%d mean wall=%.3f ms Perch CPU=%.3f ms ps CPU=%.3f ms; at 10 s cadence %.3f%% of one core", reader.lastNativeCount, reader.lastProtectedCount, wall / 20, own, child, (own + child) / 100))
}

// Exercises the real asynchronous menu sampler without opening the menu or
// changing preferences. Its lifetime is bounded; closing must stop new reads.
func runProcessCPULiveTest() throws {
    let sampler = ProcessCPUSampler()
    // Warm authenticated owner PID snapshots before the first CPU interval.
    let warm = Date().addingTimeInterval(2)
    while Date() < warm {
        _ = GuardianInstall.status
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    let opened = ProcessInfo.processInfo.systemUptime
    var firstUpdate: Double?
    sampler.onUpdate = { if firstUpdate == nil { firstUpdate = ProcessInfo.processInfo.systemUptime - opened } }
    sampler.setActive(true)
    let until = Date().addingTimeInterval(5)
    while Date() < until {
        sampler.refresh()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    let line = sampler.text
    guard let firstUpdate, firstUpdate < 3 else { throw AppError(message: "Initial CPU result did not notify the menu promptly") }
    print(String(format: "First CPU update callback: %.3f seconds", firstUpdate))
    guard !line.contains("--%"), !line.contains("Unavailable"), sampler.requests == 2 else { throw AppError(message: "CPU live sampler did not finish: " + line) }
    sampler.setActive(false)
    for _ in 0..<100 { sampler.refresh(now: ProcessInfo.processInfo.systemUptime + 100) }
    guard sampler.requests == 2 else { throw AppError(message: "Closed menu continued CPU sampling") }
    print("PASS: native/protected live CPU, two-sample startup, 10-second throttle, no closed-menu work:", line)
}
