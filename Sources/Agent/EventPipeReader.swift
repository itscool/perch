import Foundation
import Darwin

// Darwin's named FIFO write path posts its vnode/kqueue notification after
// sosend returns. A blocking write larger than the FIFO can therefore wait for
// a DispatchSourceRead consumer that never gets notified. select uses the FIFO's
// underlying socket readiness instead. A dedicated thread sleeps in select with
// no timeout; a control pipe wakes it for cancellation. See PIPELINE-INVESTIGATION.md.
final class EventPipeReader {
    private let condition = NSCondition()
    private let descriptor: Int32
    private var control: [Int32] = [-1, -1]
    private var stopped = false
    private var noticePending = false
    private var chunks: [Data] = []
    private var count = 0
    private var reads: UInt64 = 0
    private var peakBytes = 0
    private var queuedAt: UInt64?
    private var maxDeliveryMS = 0.0
    private let capacity = 262_144
    private var buffer = [UInt8](repeating: 0, count: 65_536)
    private let readable: () -> Void
    private let failed: (String) -> Void

    struct Metrics {
        let reads: UInt64
        let queued: Int
        let peak: Int
        let maxDeliveryMS: Double
        var text: String { "reads=\(reads) queued=\(queued) peak=\(peak) maxDeliveryMS=\(Int(maxDeliveryMS))" }
    }
    var metrics: Metrics {
        condition.lock(); defer { condition.unlock() }
        return Metrics(reads: reads, queued: count, peak: peakBytes, maxDeliveryMS: maxDeliveryMS)
    }
    var diagnostics: String { metrics.text }

    init(descriptor: Int32, readable: @escaping () -> Void, failed: @escaping (String) -> Void) {
        self.descriptor = descriptor; self.readable = readable; self.failed = failed
        // fd_set is bounded. Reject unsupported descriptors rather than corrupting it.
        guard descriptor >= 0, descriptor < FD_SETSIZE, pipe(&control) == 0 else {
            stopped = true; if descriptor >= 0 { close(descriptor) }
            DispatchQueue.main.async { failed("Could not initialize process-event reader.") }
            return
        }
        guard control[0] < FD_SETSIZE,
              fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK) == 0,
              control.allSatisfy({ fcntl($0, F_SETFD, FD_CLOEXEC) == 0 && fcntl($0, F_SETFL, O_NONBLOCK) == 0 }) else {
            stopped = true; close(descriptor); close(control[0]); close(control[1]); control = [-1, -1]
            DispatchQueue.main.async { failed("Could not initialize process-event reader.") }
            return
        }
        // The worker owns the reader until stop/EOF, and closes its descriptors itself.
        let worker = Thread { [self] in run() }
        worker.name = "Perch.process-pipe"; worker.qualityOfService = .userInitiated
        worker.start()
    }

    private static func include(_ fd: Int32, in set: inout fd_set) {
        withUnsafeMutableBytes(of: &set) {
            $0.bindMemory(to: UInt32.self)[Int(fd) / 32] |= UInt32(1) << (UInt32(fd) % 32)
        }
    }

    private func run() {
        defer {
            condition.lock()
            close(descriptor); close(control[0]); close(control[1]); control = [-1, -1]
            condition.unlock()
        }
        while true {
            condition.lock()
            while count >= capacity && !stopped { condition.wait() }
            let done = stopped
            condition.unlock()
            if done { return }

            var set = fd_set()
            Self.include(descriptor, in: &set); Self.include(control[0], in: &set)
            let result = select(max(descriptor, control[0]) + 1, &set, nil, nil, nil)
            let error = errno
            condition.lock()
            if stopped { condition.unlock(); return }
            if result < 0 {
                if error != EINTR { finish("Process event pipe readiness failed.") }
            } else {
                autoreleasepool { readBatch(notify: true) }
            }
            condition.unlock()
        }
    }

    // Called with condition held. All reads, including a Panic/preview drain,
    // are serialized and nonblocking; memory stays bounded without dropping bytes.
    private func readBatch(notify: Bool) {
        guard !stopped else { return }
        while count < capacity {
            let n = read(descriptor, &buffer, min(buffer.count, capacity - count))
            if n == 0 { finish("Process event collector stopped."); break }
            if n < 0 {
                if errno == EINTR { continue }
                if errno != EAGAIN { finish("Process event pipe failed.") }
                break
            }
            if chunks.isEmpty { queuedAt = DispatchTime.now().uptimeNanoseconds }
            reads += 1
            chunks.append(Data(buffer.prefix(n))); count += n
            peakBytes = max(peakBytes, count)
        }
        if notify { notifyReadable() }
    }

    private func notifyReadable() {
        if !chunks.isEmpty && !noticePending {
            noticePending = true; DispatchQueue.main.async(execute: readable)
        }
    }

    func takeAvailable() -> [Data] {
        condition.lock(); defer { condition.unlock() }
        readBatch(notify: false)
        if let start = queuedAt {
            maxDeliveryMS = max(maxDeliveryMS, Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }
        queuedAt = nil
        let result = chunks
        chunks.removeAll(keepingCapacity: true); count = 0; noticePending = false
        condition.signal()
        return result
    }

    private func finish(_ reason: String) {
        guard !stopped else { return }
        // Queue final bytes before EOF/failure, in the same order as normal delivery.
        notifyReadable()
        stopLocked()
        DispatchQueue.main.async { self.failed(reason) }
    }

    private func stopLocked() {
        guard !stopped else { return }
        stopped = true; condition.signal()
        // Only the first stop writes, so the nonblocking control pipe cannot fill.
        var byte: UInt8 = 1
        if control[1] >= 0 {
            while write(control[1], &byte, 1) < 0 && errno == EINTR {}
        }
    }

    func stop() {
        condition.lock(); stopLocked(); condition.unlock()
    }
}
