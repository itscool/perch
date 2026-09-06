import Foundation
import Darwin
@main struct PipeTest {
 static func main() throws {
  var fds: [Int32] = [-1,-1]
  precondition(pipe(&fds) == 0)
  precondition(fcntl(fds[0], F_SETFL, O_NONBLOCK) == 0)
  let input = Data((0..<1_048_576).map { UInt8($0 % 251) })
  var output = Data(); var closed = false
  var reader: EventPipeReader!
  reader = EventPipeReader(descriptor: fds[0], readable: {
   for chunk in reader.takeAvailable() { output.append(chunk) }
  }, failed: { _ in closed = true })
  let writer = fds[1]
  DispatchQueue.global().async {
   input.withUnsafeBytes { raw in
    var offset = 0
    while offset < raw.count {
     let n = write(writer, raw.baseAddress!.advanced(by:offset), raw.count-offset)
     precondition(n > 0); offset += n
    }
   }
   close(writer)
  }
  // Let the bounded reader fill before servicing its main-thread delivery callback.
  usleep(100_000)
  let deadline = Date().addingTimeInterval(10)
  while !closed && Date() < deadline { RunLoop.main.run(until:Date().addingTimeInterval(0.01)) }
  precondition(closed && output == input, "Backpressure/EOF lost or reordered bytes")
  reader.stop()
  print("PASS: bounded reader preserves 1 MiB across backpressure and EOF")
 }
}
