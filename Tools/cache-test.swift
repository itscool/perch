import Foundation
@main struct CacheTest {
 static func main() throws {
 let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
 try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
 defer { try? FileManager.default.removeItem(at: dir) }
 let file = dir.appendingPathComponent("state.json")
 func write(_ value: String) throws { try Data(value.utf8).write(to: file, options: .atomic) }
 func check(_ value: Bool) { precondition(value) }
 func read() throws -> [String:Int] { try JSONFileCache.read([String:Int].self, from: file) }
 try write("{\"v\":1}"); check(try read()["v"] == 1)
 try write("{\"v\":2}"); check(try read()["v"] == 2)
 try write("bad")
 do { _ = try read(); fatalError("Accepted corruption") } catch {}
 try write("{\"v\":3}"); check(try read()["v"] == 3)
 try FileManager.default.removeItem(at:file)
 do { _ = try read(); fatalError("Returned deleted data") } catch {}
 try write("{\"v\":4}"); check(try read()["v"] == 4)
 print("PASS: atomic replacement, corrupt data, recovery, deletion and recreation")
 }
}
