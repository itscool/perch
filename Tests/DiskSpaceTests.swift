import Foundation

/// The System section's disk lines: what they say, which disks appear, and that
/// reading them can never become a cost the person notices.
func runDiskSpaceTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    let gb: Int64 = 1_000_000_000

    // The startup disk splits into macOS and Data, then free of total.
    let main = DiskSpace.mainLine(total: 2_000 * gb, free: 994 * gb, containerUsed: 1_002 * gb, dataUsed: 978 * gb)
    try check(main.title == "Disk" && main.detail == "macOS 24 GB · Data 978 GB · 994 GB free of 2 TB", "Startup disk line reads wrongly: \(main.detail)")
    try check(!DiskSpace.mainLine(total: 100 * gb, free: 10 * gb, containerUsed: 5 * gb, dataUsed: 6 * gb).detail.contains("-"),
              "A Data volume larger than the container's use produced a negative macOS size")

    // On APFS every volume reports the whole container's use to statfs, so
    // reading Data that way made it swallow macOS, which showed as nothing. Read
    // for real, read-only: macOS must take a share of this Mac's startup disk.
    let real = DiskSpace.readNow()
    try check(real.first?.title == "Disk" && real.first?.detail.hasPrefix("macOS 0 ") == false,
              "The startup disk showed macOS taking no space: \(String(describing: real.first?.detail))")

    // Other disks: used and free, by name.
    var backup = DiskSpace.Volume(name: "Backup", path: "/Volumes/Backup", root: false, browsable: true, local: true, diskImage: false, total: 2_000 * gb, free: 800 * gb)
    try check(DiskSpace.otherLine(backup) == .init(title: "Backup", detail: "1.2 TB used · 800 GB free"), "Other disk line reads wrongly: \(DiskSpace.otherLine(backup).detail)")

    // Only disks you can open in Finder get a line. A network share is never
    // shown or read: a sleeping server stalls a size query.
    try check(DiskSpace.shows(backup), "An external disk was hidden")
    var hidden = backup; hidden.root = true
    try check(!DiskSpace.shows(hidden), "The startup volume got a second line")
    hidden = backup; hidden.browsable = false
    try check(!DiskSpace.shows(hidden), "A hidden system volume got a line")
    hidden = backup; hidden.local = false
    try check(!DiskSpace.shows(hidden), "A network share got a line")
    hidden = backup; hidden.diskImage = true
    try check(!DiskSpace.shows(hidden), "A mounted disk image got a line")
    backup.total = 0
    try check(!DiskSpace.shows(backup), "A disk reporting no size got a line")

    // Never a hog: at most one reading every 30 seconds, never two at once, and
    // never on the main thread.
    let disk = DiskSpace()
    var now = 1_000.0, reads = 0
    var pending: [() -> Void] = []
    disk.clock = { now }
    disk.read = { reads += 1; return [.init(title: "Disk", detail: "fixture")] }
    disk.schedule = { pending.append($0) }
    try check(disk.refreshIfDue(), "The first reading did not start")
    try check(!disk.refreshIfDue(), "A second reading started while the first was running")
    pending.removeFirst()()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    try check(disk.lines.count == 1 && reads == 1, "The reading did not reach the menu")
    now += 29
    try check(!disk.refreshIfDue(), "A reading ran again within 30 seconds")
    now += 1
    try check(disk.refreshIfDue() && pending.count == 1, "A reading did not run again after 30 seconds")

    let live = DiskSpace()
    var offMain: Bool?
    live.read = { offMain = !Thread.isMainThread; return [] }
    live.refreshIfDue()
    let deadline = Date().addingTimeInterval(2)
    while offMain == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    try check(offMain == true, "Disk space was read on the main thread")

    print("PASS: disk lines: macOS, Data and free of total for the startup disk, used and free for each other disk you can open in Finder; network shares, disk images and hidden volumes never read; at most one reading every 30 seconds, never two at once, never on the main thread")
}
