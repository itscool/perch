import Foundation
import Darwin
@main struct AnchorTest {
 static func main() throws {
  let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
  precondition(mkfifo(path, 0o600) == 0)
  defer { unlink(path) }
  let anchor = CollectorPipeAnchor(path:path); anchor.refresh()
  let writer = open(path,O_WRONLY | O_NONBLOCK)
  precondition(writer >= 0); defer { close(writer) }
  var consumer = open(path,O_RDONLY | O_NONBLOCK)
  precondition(consumer >= 0); close(consumer)
  // During the consumer's restart, the writer remains connected and bytes stay queued.
  let data = Data("restart fixture".utf8)
  let written = data.withUnsafeBytes { write(writer,$0.baseAddress,$0.count) }
  precondition(written == data.count)
  consumer = open(path,O_RDONLY | O_NONBLOCK)
  precondition(consumer >= 0); defer { close(consumer) }
  var bytes = [UInt8](repeating:0,count:100)
  let count = read(consumer,&bytes,bytes.count)
  precondition(count == data.count && Data(bytes.prefix(count)) == data)
  withExtendedLifetime(anchor) {}
  print("PASS: collector connection survives consumer restart without consuming its events")
 }
}
