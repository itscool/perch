import Foundation
import Darwin

// Keeps a reader attached while the monitor restarts, preventing a writer-side
// broken pipe. This helper never consumes bytes; only the monitor reads events.
final class CollectorPipeAnchor {
    let path: String
    private var descriptor: Int32 = -1
    private var inode: UInt64?
    init(path: String) { self.path = path }
    func refresh() {
        var info = stat()
        guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFIFO,
              info.st_uid == getuid(), info.st_mode & 0o077 == 0 else { closeCurrent(); return }
        guard descriptor < 0 || inode != info.st_ino else { return }
        closeCurrent()
        let fd = open(path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return }
        var actual = stat()
        guard fstat(fd, &actual) == 0, actual.st_ino == info.st_ino,
              (actual.st_mode & S_IFMT) == S_IFIFO, actual.st_uid == getuid(), actual.st_mode & 0o077 == 0 else { close(fd); return }
        descriptor = fd; inode = actual.st_ino
    }
    private func closeCurrent() {
        if descriptor >= 0 { close(descriptor) }
        descriptor = -1; inode = nil
    }
    deinit { closeCurrent() }
}
