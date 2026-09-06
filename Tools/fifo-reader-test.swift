import Foundation
import Darwin

// Regression for Darwin FIFO/kqueue deadlock on blocking writes > FIFO capacity.
// Compile with EventPipeReader.swift. Uses only temporary FIFOs and fixture bytes.
@main struct FIFOReaderTest {
    static func pump(until done: () -> Bool, seconds: Double = 3) {
        let deadline = Date().addingTimeInterval(seconds)
        while !done() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
    }
    static func main() {
        signal(SIGPIPE, SIG_IGN) // A failing test can close its own blocked fixture writer.
        for size in [4096, 65536, 2_097_152] {
            let path = "/private/tmp/perch-fifo-test-\(UUID().uuidString)"
            precondition(mkfifo(path, 0o600) == 0)
            let fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
            let writer = open(path, O_WRONLY | O_CLOEXEC)
            let input = Data((0..<size).map { UInt8($0 % 251) })
            var output = Data(); var ended = false
            var reader: EventPipeReader!
            reader = EventPipeReader(descriptor: fd, readable: {
                for data in reader.takeAvailable() { output.append(data) }
            }, failed: { _ in ended = true })
            let finished = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                // Ensure readiness registration precedes the blocking write.
                usleep(100_000)
                input.withUnsafeBytes { raw in
                    var sent = 0
                    while sent < raw.count {
                        let n = write(writer, raw.baseAddress!.advanced(by: sent), raw.count - sent)
                        if n < 0 && errno == EINTR { continue }
                        if n <= 0 { break }; sent += n
                    }
                }
                // Keep writer open until the reader has delivered every byte.
                finished.signal()
            }
            // Force bounded-queue backpressure on the largest fixture.
            usleep(180_000)
            pump(until: { output.count == size })
            let passed = output == input && !ended
            print("\(passed ? "PASS" : "FAIL"): named FIFO blocking write \(size) bytes, received \(output.count) before EOF")
            fflush(stdout)
            reader.stop()
            precondition(finished.wait(timeout: .now() + 1) == .success, "Fixture writer did not terminate")
            close(writer); unlink(path)
            precondition(passed, "Large write stalled or data changed")
        }
        // EOF delivers final bytes before failure, even without another write.
        let path = "/private/tmp/perch-fifo-eof-\(UUID().uuidString)"
        precondition(mkfifo(path, 0o600) == 0)
        let fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        let writer = open(path, O_WRONLY | O_CLOEXEC)
        var output = Data(); var ended = false
        var reader: EventPipeReader!
        reader = EventPipeReader(descriptor: fd, readable: {
            for data in reader.takeAvailable() { output.append(data) }
        }, failed: { _ in ended = true })
        precondition(write(writer, [UInt8](repeating: 42, count: 100), 100) == 100)
        close(writer)
        pump(until: { ended })
        precondition(ended && output == Data(repeating: 42, count: 100))
        reader.stop(); unlink(path)
        print("PASS: EOF preserves final bytes")

        // Cancellation must release a reader asleep with a live, idle writer.
        let idlePath = "/private/tmp/perch-fifo-idle-\(UUID().uuidString)"
        precondition(mkfifo(idlePath, 0o600) == 0)
        let idle = open(idlePath, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        let idleWriter = open(idlePath, O_WRONLY | O_CLOEXEC)
        var idleReader: EventPipeReader? = EventPipeReader(descriptor: idle, readable: {}, failed: { _ in preconditionFailure("Explicit stop reported failure") })
        weak var weakReader = idleReader
        usleep(50_000); idleReader?.stop(); idleReader = nil
        pump(until: { weakReader == nil })
        precondition(weakReader == nil && fcntl(idle, F_GETFD) < 0)
        close(idleWriter); unlink(idlePath)
        print("PASS: idle cancellation releases worker and descriptors")
    }
}
