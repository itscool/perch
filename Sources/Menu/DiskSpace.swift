import Foundation
import DiskArbitration

/// Disk space for the System section: this Mac's own disk split into macOS and
/// Data, then one line per other disk you can open in Finder.
///
/// "macOS" is everything on the startup disk that is not the Data volume: the
/// sealed system, its preboot and recovery copies and virtual memory. "Data" is
/// everything else, which includes apps, caches and other accounts as well as
/// your own files. Counting only your files would mean walking the whole disk,
/// far too slow for a menu, so the split is the one macOS itself keeps.
///
/// Free space is Finder's figure, which counts space macOS will clear on its own,
/// so the two never disagree.
///
/// It must never cost the Mac anything noticeable. Readings happen off the main
/// thread, at most once every 30 seconds, and only while the menu is open; the
/// menu shows the last reading meanwhile. Network shares are never read: a
/// sleeping server can stall a size query for many seconds. Disk images and the
/// hidden system volumes are not shown.
final class DiskSpace {
    struct Line: Equatable {
        let title: String
        let detail: String
    }
    /// A volume as Perch decides whether to show it.
    struct Volume: Equatable {
        var name: String
        var path: String
        var root: Bool
        var browsable: Bool
        var local: Bool
        var diskImage: Bool
        var total: Int64
        var free: Int64
    }
    static let interval: TimeInterval = 30
    static let help = "macOS is the system itself, its recovery copies and virtual memory. Data is everything else on the startup disk, including apps and caches as well as your files. Free space matches Finder. Other disks appear when you can open them in Finder; network shares and disk images are not read."
    private(set) var lines: [Line] = []
    var changed: () -> Void = {}
    private var reading = false
    private var lastRead: TimeInterval = -.infinity
    private let queue = DispatchQueue(label: "Perch.disk-space", qos: .utility)
    /// Injected so tests can count reads and run them synchronously.
    var read: () -> [Line] = { DiskSpace.readNow() }
    var clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    var schedule: (@escaping () -> Void) -> Void

    init() {
        let queue = self.queue
        schedule = { work in queue.async(execute: work) }
    }

    /// Start a reading if the last one is old enough and none is running.
    /// Returns whether it started one.
    @discardableResult
    func refreshIfDue() -> Bool {
        let now = clock()
        guard !reading, now - lastRead >= Self.interval else { return false }
        reading = true
        lastRead = now
        let read = self.read
        schedule { [weak self] in
            let lines = read()
            DispatchQueue.main.async {
                guard let self else { return }
                self.reading = false
                if self.lines != lines { self.lines = lines; self.changed() }
            }
        }
        return true
    }

    // MARK: What is shown

    /// The startup disk: what macOS takes, what Data takes, and what is free.
    static func mainLine(total: Int64, free: Int64, containerUsed: Int64, dataUsed: Int64) -> Line {
        let system = max(0, containerUsed - dataUsed)
        return Line(title: "Disk", detail: "macOS \(size(system)) · Data \(size(dataUsed)) · \(size(free)) free of \(size(total))")
    }
    static func otherLine(_ volume: Volume) -> Line {
        Line(title: volume.name, detail: "\(size(max(0, volume.total - volume.free))) used · \(size(volume.free)) free")
    }
    /// Whether a disk other than the startup disk gets its own line.
    static func shows(_ volume: Volume) -> Bool {
        !volume.root && volume.browsable && volume.local && !volume.diskImage && volume.total > 0
    }
    /// Decimal units, as Finder shows them, to three significant figures:
    /// "947 GB", "1.05 TB", "26.3 GB".
    static func size(_ bytes: Int64) -> String {
        var value = Double(max(0, bytes)), unit = 0
        let units = ["bytes", "KB", "MB", "GB", "TB", "PB"]
        while value >= 1000, unit < units.count - 1 { value /= 1000; unit += 1 }
        let number = NumberFormatter()
        number.usesSignificantDigits = true
        number.maximumSignificantDigits = 3
        return (number.string(from: NSNumber(value: value)) ?? String(Int(value))) + " " + units[unit]
    }

    // MARK: Reading

    static func readNow() -> [Line] {
        var lines: [Line] = []
        if let main = startupDisk() { lines.append(main) }
        lines += otherVolumes().filter(shows).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.map(otherLine)
        return lines
    }
    private static func startupDisk() -> Line? {
        // Every volume in the startup container shares one pool, so "/" gives
        // the container's size and strict free space, and the Data volume its
        // own use. Finder's free figure also counts space macOS can clear.
        guard let container = statistics("/"), let dataUsed = spaceUsed("/System/Volumes/Data") else { return nil }
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let free = values?.volumeAvailableCapacityForImportantUsage ?? container.free
        return mainLine(total: container.total, free: free, containerUsed: container.total - container.free, dataUsed: dataUsed)
    }
    /// The container's size and its strict free space. On APFS every volume
    /// reports the whole container here, both its size and its free blocks.
    private static func statistics(_ path: String) -> (total: Int64, free: Int64)? {
        var info = statfs()
        guard statfs(path, &info) == 0 else { return nil }
        let block = Int64(info.f_bsize)
        return (Int64(info.f_blocks) * block, Int64(info.f_bavail) * block)
    }
    /// One volume's own use, which statfs cannot give on APFS (it reports the
    /// container), read the way df does.
    private static func spaceUsed(_ path: String) -> Int64? {
        var list = attrlist()
        list.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        list.volattr = attrgroup_t(ATTR_VOL_INFO) | attrgroup_t(ATTR_VOL_SPACEUSED)
        var buffer = [UInt8](repeating: 0, count: 64)
        guard getattrlist(path, &list, &buffer, buffer.count, 0) == 0 else { return nil }
        // The reply is a 32-bit length followed by the 64-bit size, packed.
        return buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: Int64.self) }
    }
    private static func otherVolumes() -> [Volume] {
        // Only what the mount table already knows, so listing never touches a
        // disk or a server.
        let listing: [URLResourceKey] = [.volumeNameKey, .volumeIsRootFileSystemKey, .volumeIsBrowsableKey, .volumeIsLocalKey]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: listing, options: [.skipHiddenVolumes]) else { return [] }
        let session = DASessionCreate(kCFAllocatorDefault)
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(listing)) else { return nil }
            // Never ask a network share for its size; a sleeping server stalls.
            guard values.volumeIsLocal == true else { return nil }
            let sizes = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
            return Volume(name: values.volumeName ?? url.lastPathComponent, path: url.path,
                          root: values.volumeIsRootFileSystem ?? false, browsable: values.volumeIsBrowsable ?? false,
                          local: true, diskImage: session.map { isDiskImage(url, session: $0) } ?? false,
                          total: Int64(sizes?.volumeTotalCapacity ?? 0), free: Int64(sizes?.volumeAvailableCapacity ?? 0))
        }
    }
    private static func isDiskImage(_ url: URL, session: DASession) -> Bool {
        guard let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL),
              let description = DADiskCopyDescription(disk) as? [CFString: Any] else { return false }
        let model = description[kDADiskDescriptionDeviceModelKey] as? String ?? ""
        let transport = description[kDADiskDescriptionDeviceProtocolKey] as? String ?? ""
        return model.contains("Disk Image") || transport == "Virtual Interface"
    }
}
