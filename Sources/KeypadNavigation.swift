import Foundation

/// Per-external-device Num Lock state. Only keypad virtual key codes are kept;
/// no text, timing guesses, or last-used-keyboard attribution.
final class KeypadNavigation {
    enum Output: Equatable { case original, key(Int64, UInt16), suppress }
    struct Press { var sender: UInt64; var key: Int64; var output: Output }
    var enabled = false
    var externalSenders = Set<UInt64>()
    func setDevices(_ ids: Set<UInt64>) { externalSenders = ids; navigationSenders.formIntersection(ids) }
    private(set) var navigationSenders = Set<UInt64>()
    private var held = [Press?](repeating: nil, count: 64)
    var hasHeldKeys: Bool { held.contains { $0 != nil } }
    static let clear: Int64 = 71
    // 7/8/9, 4/5/6, 1/2/3, 0/decimal. Operators and Enter stay native.
    static let navigation: [Int64: Output] = [
        89: .key(115, 0xF729), 91: .key(126, 0xF700), 92: .key(116, 0xF72C),
        86: .key(123, 0xF702), 87: .suppress, 88: .key(124, 0xF703),
        83: .key(119, 0xF72B), 84: .key(125, 0xF701), 85: .key(121, 0xF72D),
        82: .key(114, 0xF727), 65: .key(117, 0xF728)
    ]
    func event(sender: UInt64, key: Int64, down: Bool, repeating: Bool, commandModifiers: Bool) -> Output {
        guard key == Self.clear || Self.navigation[key] != nil else { return .original }
        if let index = held.firstIndex(where: { $0?.sender == sender && $0?.key == key }), let press = held[index] {
            if !down { held[index] = nil }
            return press.output
        }
        guard down, !repeating, enabled, sender != 0, externalSenders.contains(sender),
              let slot = held.firstIndex(where: { $0 == nil }) else { return .original }
        let output: Output
        if key == Self.clear && !commandModifiers {
            if !navigationSenders.insert(sender).inserted { navigationSenders.remove(sender) }
            output = .suppress
        } else if navigationSenders.contains(sender) {
            output = Self.navigation[key] ?? .original
        } else { output = .original }
        held[slot] = Press(sender: sender, key: key, output: output)
        return output
    }
    func navigationDisabled() { navigationSenders = [] }
    func reset(keepingMode: Bool = false) { held = Array(repeating: nil, count: 64); if !keepingMode { navigationSenders = [] } }
}
