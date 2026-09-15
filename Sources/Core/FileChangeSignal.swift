import Foundation
import Darwin

// A vnode signal follows atomic file replacement. The periodic check repairs a missing
// watch; ordinary configuration changes and queued requests are delivered immediately.
final class FileChangeSignal {
    let url: URL
    let changed: () -> Void
    var source: DispatchSourceFileSystemObject?
    var inode: UInt64?
    private var revision: FileRevision?
    init(_ url: URL, changed: @escaping () -> Void) { self.url = url; self.changed = changed; refresh() }
    @discardableResult func refresh() -> Bool {
        let latest = FileRevision.read(url)
        let modified = latest != revision
        revision = latest
        let current = latest?.inode
        guard current != inode || (current != nil && source == nil) else { return modified }
        source?.cancel(); source = nil; inode = nil
        guard current != nil else { return modified }
        let fd = open(url.path, O_EVTONLY | O_CLOEXEC | O_NOFOLLOW)
        guard fd >= 0 else { return modified }
        var info = stat()
        guard fstat(fd, &info) == 0 else { close(fd); return modified }
        inode = info.st_ino
        let signal = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .revoke], queue: .main)
        signal.setEventHandler { [weak self] in self?.refresh(); self?.changed() }
        signal.setCancelHandler { close(fd) }
        source = signal; signal.resume()
        return modified
    }
    deinit { source?.cancel() }
}
