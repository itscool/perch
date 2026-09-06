import Foundation
import Darwin

enum EventJSON { enum Invalid: Error { case json } }

// Valid only during the synchronous event callback. The parser and comparisons
// borrow the current JSONL record; only retained tracking data becomes Strings.
struct EventText {
    let input: UnsafePointer<UInt8>
    let raw: PerchJSONText
    var present: Bool { raw.flags & 1 != 0 }
    private func compare(_ value: String, _ operation: (UnsafePointer<UInt8>?, PerchJSONText, UnsafePointer<UInt8>?, Int) -> Bool) -> Bool {
        // Native UTF-8 strings (configuration/catalog data) already provide storage.
        if let result = value.utf8.withContiguousStorageIfAvailable({ operation(input, raw, $0.baseAddress, $0.count) }) { return result }
        // Unusual bridged strings may need normalization outside the C parser.
        var native = value
        return native.withUTF8 { operation(input, raw, $0.baseAddress, $0.count) }
    }
    func equals(_ value: String) -> Bool { compare(value, perch_text_equal) }
    func hasPrefix(_ value: String) -> Bool { compare(value, perch_text_prefix) }
    func contains(_ value: String) -> Bool { compare(value, perch_text_contains) }
    func basenameEquals(_ value: String) -> Bool { compare(value, perch_text_basename) }
    func retainedString() -> String {
        String(unsafeUninitializedCapacity: Int(raw.length)) {
            perch_text_copy(input, raw, $0.baseAddress, $0.count)
        }
    }
}
struct BorrowedEventProcess {
    let input: UnsafePointer<UInt8>
    let raw: PerchEventProcess
    var token: EventToken {
        let a = raw.token.values
        return .init(auid: a.0, euid: a.1, egid: a.2, ruid: a.3, rgid: a.4, pid: a.5, asid: a.6, pidversion: a.7)
    }
    var path: EventText { .init(input: input, raw: raw.path) }
    var signingID: EventText { .init(input: input, raw: raw.signing_id) }
    func retained() -> EventProcess { .init(token: token, path: path.retainedString(), signingID: signingID.present ? signingID.retainedString() : nil) }
}
struct BorrowedProcessEvent {
    let input: UnsafePointer<UInt8>
    let raw: PerchParsedEvent
    var kind: ProcessEvent.Kind { raw.kind == 1 ? .fork : raw.kind == 2 ? .exec : .exit }
    var actor: BorrowedEventProcess { .init(input: input, raw: raw.actor) }
    var subject: BorrowedEventProcess { .init(input: input, raw: raw.subject) }
    var sequence: UInt64 { raw.sequence }
    var sourceTime: EventText { .init(input: input, raw: raw.time) }
    private func argument(_ index: Int) -> EventText {
        let args = raw.arguments
        return .init(input: input, raw: index == 0 ? args.0 : index == 1 ? args.1 : index == 2 ? args.2 : args.3)
    }
    var usesArguments: Bool { kind == .exec && subject.token.ruid == getuid() && (subject.path.basenameEquals("node") || subject.path.basenameEquals("bun")) }
    func argumentsContain(_ text: String) -> Bool {
        for i in 0..<Int(raw.argument_count) where argument(i).contains(text) { return true }
        return false
    }
    func retained() -> ProcessEvent {
        var arguments: [String] = []
        if usesArguments { for i in 0..<Int(raw.argument_count) { arguments.append(argument(i).retainedString()) } }
        return .init(kind: kind, actor: actor.retained(), subject: subject.retained(), sequence: sequence, arguments: arguments, sourceTime: sourceTime.present ? sourceTime.retainedString() : nil)
    }
    static func withBytes<R>(_ bytes: UnsafeRawBufferPointer, _ body: (BorrowedProcessEvent) throws -> R) throws -> R {
        var parsed = PerchParsedEvent()
        let input = bytes.bindMemory(to: UInt8.self).baseAddress
        guard perch_event_parse(input, bytes.count, &parsed), let input else { throw EventJSON.Invalid.json }
        let event = BorrowedProcessEvent(input: input, raw: parsed)
        guard !event.usesArguments || !parsed.arguments_present || parsed.arguments_valid else { throw EventJSON.Invalid.json }
        return try body(event)
    }
}
