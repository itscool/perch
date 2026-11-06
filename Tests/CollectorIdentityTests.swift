import Foundation
import Darwin

func runCollectorIdentityTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("perch-identity-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("collector.json")
    let boot = CollectorIdentity.bootID!, birth = ProcessCPUReader.birth(getpid())!
    let record = CollectorIdentity(schema: 1, pid: getpid(), birth: birth, boot: boot)
    func write(_ data: Data) throws {
        try? FileManager.default.removeItem(at: file)
        try data.write(to: file); chmod(file.path, 0o644)
    }
    try write(JSONEncoder().encode(record))
    try check(CollectorIdentity.read(directory: root.path, owner: getuid()) == record, "Valid protected identity was rejected")
    try check(record.matches(boot: boot, birth: birth) && !record.matches(boot: UUID(), birth: birth) && !record.matches(boot: boot, birth: birth + 1) && !record.matches(boot: boot, birth: nil), "Reboot, reused PID or exited collector was accepted")
    try check(CollectorIdentity.attribution(record: record, expected: true, boot: boot, birth: { _ in birth }) == .verified(record), "Valid collector attribution failed")
    try check(CollectorIdentity.attribution(record: nil, expected: false, boot: boot, birth: { _ in nil }) == .absent, "Absent optional collector made CPU unavailable")
    try check(!CollectorIdentity.attribution(record: nil, expected: true, boot: boot, birth: { _ in nil }).complete, "Missing/unreadable collector silently disappeared from CPU total")
    try check(!CollectorIdentity.attribution(record: record, expected: false, boot: boot, birth: { _ in birth + 1 }).complete, "Reused PID became a complete total")
    let other = CollectorIdentity(schema: 2, pid: record.pid, birth: birth, boot: boot)
    try check(!other.matches(boot: boot, birth: birth), "Unknown identity protocol accepted")
    try check(CollectorIdentity.read(directory: root.path, owner: getuid() + 1) == nil, "Wrong file owner trusted")
    chmod(file.path, 0o666)
    try check(CollectorIdentity.read(directory: root.path, owner: getuid()) == nil, "Writable identity trusted")
    chmod(file.path, 0o644); chmod(root.path, 0o777)
    try check(CollectorIdentity.read(directory: root.path, owner: getuid()) == nil, "Writable parent trusted")
    chmod(root.path, 0o755)
    let link = root.appendingPathComponent("hardlink")
    try FileManager.default.linkItem(at: file, to: link)
    try check(CollectorIdentity.read(directory: root.path, owner: getuid()) == nil, "Hard-linked identity trusted")
    try FileManager.default.removeItem(at: file)
    try FileManager.default.createSymbolicLink(at: file, withDestinationURL: link)
    try check(CollectorIdentity.read(directory: root.path, owner: getuid()) == nil, "Identity symlink followed")
    try FileManager.default.removeItem(at: file)
    try check(mkfifo(file.path, 0o600) == 0 && CollectorIdentity.read(directory: root.path, owner: getuid()) == nil, "FIFO was followed or blocked")
    try write(Data(repeating: 65, count: 1025))
    try check(CollectorIdentity.read(directory: root.path, owner: getuid()) == nil, "Oversize identity trusted")
    try write(Data("{broken".utf8))
    try check(CollectorIdentity.read(directory: root.path, owner: getuid()) == nil, "Malformed identity trusted")
    try check(!EventCollectorSetup.supportedArguments(["/usr/bin/eslogger", "fork", "exec", "exit"]) && EventCollectorSetup.supportedArguments([CollectorIdentity.launcher]) && !EventCollectorSetup.supportedArguments(["/bin/sh", "collector.sh"]) && !EventCollectorSetup.supportedArguments([CollectorIdentity.launcher, "override"]), "Unsupported collector command accepted")
    try check(!EventCollectorSetup.supportedOutput(["StandardOutPath": ProcessEventStream.pipePath, "StandardErrorPath": "/dev/null"]) && EventCollectorSetup.supportedOutput(["StandardErrorPath": "/dev/null"]), "A job that lets launchd create the event pipe was accepted")
    // A pipe that is not this user's private FIFO is a broken collector, reported and never read.
    let pipe = root.appendingPathComponent("events.pipe").path
    try check(ProcessEventStream.pipeProblem(at: pipe)?.contains("missing") == true, "Missing event pipe was not reported")
    try check(mkfifo(pipe, 0o600) == 0 && ProcessEventStream.pipeProblem(at: pipe) == nil, "Private event FIFO was refused")
    chmod(pipe, 0o644)
    try check(ProcessEventStream.pipeProblem(at: pipe)?.contains("not private") == true, "Shared event FIFO was accepted")
    unlink(pipe)
    try Data("eslogger output\n".utf8).write(to: URL(fileURLWithPath: pipe))
    try check(ProcessEventStream.pipeProblem(at: pipe)?.contains("ordinary file") == true, "Ordinary file at the event pipe was accepted")
    let stream = ProcessEventStream(path: pipe)
    stream.connect()
    try check(stream.fd < 0 && stream.reader == nil && stream.failure?.contains("ordinary file") == true && stream.failure?.contains("broken") == true, "Ordinary file was read as the event stream or not reported")
    unlink(pipe); symlink(file.path, pipe)
    try check(ProcessEventStream.pipeProblem(at: pipe)?.contains("symbolic link") == true, "Event pipe symlink was accepted")
    unlink(pipe); mkdir(pipe, 0o700)
    try check(ProcessEventStream.pipeProblem(at: pipe)?.contains("not a named pipe") == true, "Directory at the event pipe was accepted")
    print("PASS: collector boot/birth identity, PID reuse/exit, optional/missing/unreadable accounting, ownership/mode/link/FIFO/size validation, fixed launcher command, no launchd-created output, and a missing, shared, ordinary-file, symlink or directory event pipe reported and never read; fixture storage only")
}
