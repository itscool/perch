import Foundation
@main struct SignalTest {
 static func main() throws {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: dir) }
  let file = dir.appendingPathComponent("config.json")
  try Data("1".utf8).write(to:file, options:.atomic)
  var calls = 0
  let watch = FileChangeSignal(file) { calls += 1 }
  func wait(_ predicate: () -> Bool) {
   let deadline = Date().addingTimeInterval(2)
   while !predicate() && Date() < deadline { RunLoop.main.run(until:Date().addingTimeInterval(0.01)) }
   precondition(predicate(), "File change notification was lost")
  }
  for n in 2...5 {
   let before = calls
   try Data(String(n).utf8).write(to:file, options:.atomic)
   wait { calls > before }
   precondition(watch.inode == FileRevision.read(file)?.inode)
  }
  try FileManager.default.removeItem(at:file)
  wait { watch.inode == nil }
  try Data("6".utf8).write(to:file, options:.atomic)
  watch.refresh()
  let before = calls
  try Data("7".utf8).write(to:file, options:.atomic)
  wait { calls > before }
  var requests = 0
  let directory = FileChangeSignal(dir) { requests += 1 }
  try Data("request".utf8).write(to:dir.appendingPathComponent("request.json"), options:.atomic)
  wait { requests > 0 }
  withExtendedLifetime((watch,directory)) {}
  print("PASS: repeated atomic replacement, deletion/recreation, and queued-request directory signals")
 }
}
