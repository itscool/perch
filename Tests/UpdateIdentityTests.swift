import AppKit
import CryptoKit

func runUpdateIdentityTests() throws {
    func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw AppError(message: message) }
    }
    let key = Curve25519.Signing.PrivateKey()
    let identity = UpdateIdentity(schema: 1, bundle: "local.perch.fixture", build: "84", codeHash: String(repeating: "a", count: 40), requirement: "same publisher", lidProtocol: 2)
    let data = try JSONEncoder().encode(identity)
    let signature = try key.signature(for: data).base64EncodedString()
    func verify(_ payload: String = data.base64EncodedString(), signature signed: String = signature,
                publicKey: String = key.publicKey.rawRepresentation.base64EncodedString(), build: String = "84",
                requirement: String = "same publisher", lidProtocol: Int = 2) throws -> UpdateIdentity {
        try UpdateIdentity.verify(payload: payload, signature: signed, publicKey: publicKey,
                                  bundle: "local.perch.fixture", build: build, requirement: requirement, lidProtocol: lidProtocol)
    }
    let verified = try verify()
    try check(verified == identity, "Valid Ed25519 update identity rejected")
    let invalid: [() throws -> UpdateIdentity] = [
        { try verify(Data("{}".utf8).base64EncodedString()) },
        { try verify(signature: Data(repeating: 0, count: 64).base64EncodedString()) },
        { try verify(publicKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()) },
        { try verify(build: "85") }, { try verify(requirement: "new publisher") }, { try verify(lidProtocol: 3) },
        { try verify(String(repeating: "A", count: 16_388)) }
    ]
    for attempt in invalid {
        var rejected = false
        do { _ = try attempt() } catch { rejected = true }
        try check(rejected, "Untrusted/mismatched update identity was accepted")
    }
    let boot = UUID(), ticket = LidRestartTicket(id: UUID().uuidString, targetIdentity: identity.codeHash, deadline: 160)
    let record = NetworkUpdateHandoff(boot: boot, path: "/fixture/Perch.app", build: "84", ticket: ticket)
    try check(record.matches(boot: boot, path: record.path, build: "84", identity: identity.codeHash, now: 120), "Valid handoff rejected")
    try check(!record.matches(boot: UUID(), path: record.path, build: "84", identity: identity.codeHash, now: 120), "Ticket crossed reboot")
    try check(!record.matches(boot: boot, path: "/another/Perch.app", build: "84", identity: identity.codeHash, now: 120), "Another installation claimed ticket")
    try check(!record.matches(boot: boot, path: record.path, build: "83", identity: identity.codeHash, now: 120), "Old build claimed ticket")
    try check(!record.matches(boot: boot, path: record.path, build: "84", identity: String(repeating: "b", count: 40), now: 120), "Different code claimed ticket")
    for time in [99.0, 160.0, 180.0, .nan, .infinity] {
        try check(!record.matches(boot: boot, path: record.path, build: "84", identity: identity.codeHash, now: time), "Out-of-window handoff accepted")
    }
    // Storage is redirected by the functional runner; never invoke the helper.
    if Bundle.main.bundleIdentifier == "local.perch.functional-review" {
        defer { NetworkUpdateHandoffFile.remove() }
        try NetworkUpdateHandoffFile.save(record)
        try check(NetworkUpdateHandoffFile.read()?.ticket == ticket, "Durable handoff did not round-trip")
        NetworkUpdateHandoffFile.remove()
        try FileManager.default.createSymbolicLink(at: NetworkUpdateHandoffFile.url, withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
        try check(NetworkUpdateHandoffFile.read() == nil, "Handoff followed symlink")
        NetworkUpdateHandoffFile.remove()
        try Data(repeating: 0, count: 9000).write(to: NetworkUpdateHandoffFile.url)
        try check(NetworkUpdateHandoffFile.read() == nil, "Oversized record accepted")
        let host = SettingsWindow.shared, depth = SettingsWindow.shared.pages.count
        let app = AppDelegate()
        app.updateSettings()
        guard let page = host.pages.last else { throw AppError(message: "Updates page did not open") }
        let buttons = page.view.subviews.compactMap { $0 as? NSButton }
        try check(buttons.count == 2 && buttons.allSatisfy { !$0.isEnabled }, "Unconfigured updater offered a dead action or orphaned retry")
        try check(page.view.subviews.compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("not configured") }, "Unconfigured updater did not explain availability")
        host.goBack()
        try check(host.pages.count == depth, "Updates Back did not leave the page")
    }
    print("PASS: signed update identity, publisher/protocol/build binding, tamper rejection, bounded handoff and safe storage")
}
