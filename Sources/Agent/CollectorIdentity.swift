import Foundation
import Darwin

struct CollectorIdentity: Codable, Equatable {
    let schema: Int
    let pid: Int32
    let birth: UInt64
    let boot: UUID
    static let directory = "/Library/Application Support/Perch Events"
    static let launcher = directory + "/PerchEventLauncher"
    static let job = "/Library/LaunchDaemons/local.scott.perch.events.plist"
    static var bootID: UUID? {
        var bytes = [CChar](repeating: 0, count: 64), size = 64
        guard sysctlbyname("kern.bootsessionuuid", &bytes, &size, nil, 0) == 0, size <= bytes.count, bytes.last == 0 else { return nil }
        return UUID(uuidString: String(cString: bytes))
    }
    func matches(boot currentBoot: UUID?, birth liveBirth: UInt64?) -> Bool {
        schema == 1 && pid > 1 && birth > 0 && currentBoot == boot && liveBirth == birth
    }
    // Descriptor-relative, bounded reads: never follow a record symlink, block
    // on a FIFO, or trust a user-writable identity supplied as a root observation.
    static func read(directory path: String = directory, owner: uid_t = 0) -> Self? {
        let dir = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard dir >= 0 else { return nil }; defer { close(dir) }
        var parent = stat()
        guard fstat(dir, &parent) == 0, parent.st_uid == owner, parent.st_mode & 0o022 == 0 else { return nil }
        let fd = openat(dir, "collector.json", O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { return nil }; defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == owner, info.st_mode & 0o022 == 0, info.st_nlink == 1,
              info.st_size > 0, info.st_size <= 1024 else { return nil }
        var data = Data(count: Int(info.st_size))
        let count = data.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
        guard count == data.count else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
    static func fileMayExist(_ path: String) -> Bool {
        var info = stat()
        if lstat(path, &info) == 0 { return true }
        return errno != ENOENT // Unreadable is unknown, not absent.
    }
    static func attribution(record: Self?, expected: Bool, boot: UUID?, birth: (Int32) -> UInt64?) -> CollectorAttribution {
        if let record, record.matches(boot: boot, birth: birth(record.pid)) { return .verified(record) }
        return expected || record != nil ? .unavailable : .absent
    }
    static func current() -> CollectorAttribution {
        attribution(record: read(), expected: fileMayExist(job) || fileMayExist(directory + "/collector.json"), boot: bootID, birth: ProcessCPUReader.birth)
    }
}
enum CollectorAttribution: Equatable {
    case absent, unavailable, verified(CollectorIdentity)
    var complete: Bool { if case .unavailable = self { return false }; return true }
    var identity: CollectorIdentity? { if case .verified(let identity) = self { return identity }; return nil }
}
