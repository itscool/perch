import Foundation

/// A bounded, read-only diagnostic. It stores four press/release states, never text.
enum NavigationKey: UInt32, CaseIterable {
    case home = 0x4A, end = 0x4D, pageUp = 0x4B, pageDown = 0x4E
    var name: String {
        switch self { case .home: return "Home"; case .end: return "End"; case .pageUp: return "Page Up"; case .pageDown: return "Page Down" }
    }
}

enum NavigationDeviceScope {
    static func isExternal(builtIn: Bool?, transport: String) -> Bool {
        guard builtIn != true else { return false }
        // Unknown, virtual, SPI and internal transports fail closed. USB alone
        // is insufficient if the device or its registry ancestry says Built-In.
        return ["USB", "Bluetooth", "Bluetooth Low Energy"].contains(transport)
    }
}

struct NavigationProbeState {
    enum Phase: Equatable { case idle, listening, complete, incomplete, stopped(String) }
    struct KeyState {
        var held = false
        var pressed = false
        var released = false
        var usage: UInt32?
        var absent = false
        var complete: Bool { absent || (pressed && released && !held) }
    }
    private(set) var phase: Phase = .idle
    private(set) var keys = NavigationKey.allCases.map { _ in KeyState() }
    private(set) var deviceID: UInt64 = 0
    private(set) var deadline: TimeInterval = 0
    private(set) var guided = false
    private(set) var notice: String?
    var currentKey: NavigationKey? { keys.firstIndex(where: { !$0.complete }).map { NavigationKey.allCases[$0] } }
    var learnedKeys: [UInt32?]? { phase == .complete ? keys.map { $0.usage } : nil }
    var listening: Bool { phase == .listening }
    mutating func start(deviceID: UInt64, now: TimeInterval, guided: Bool = false) {
        self = NavigationProbeState()
        guard deviceID != 0 else { phase = .stopped("Keyboard identity unavailable."); return }
        self.deviceID = deviceID; self.guided = guided; deadline = now + (guided ? 60 : 30); phase = .listening
    }
    @discardableResult
    mutating func receive(deviceID: UInt64, page: UInt32, usage: UInt32, value: Int, now: TimeInterval) -> Bool {
        guard listening else { return false }
        if now >= deadline { phase = .incomplete; return true }
        guard self.deviceID == deviceID, page == 7, value == 0 || value == 1 else { return false }
        let index: Int
        if guided {
            guard NavigationLearning.allowed(usage), let next = keys.firstIndex(where: { !$0.complete }) else { return false }
            index = next
            if keys.contains(where: { $0.complete && $0.usage == usage }) {
                notice = "That key is already assigned. Press \(NavigationKey.allCases[index].name), or mark it absent."; return true
            }
            if keys[index].held && keys[index].usage != usage { return false }
        } else {
            guard let key = NavigationKey(rawValue: usage), let match = NavigationKey.allCases.firstIndex(of: key) else { return false }
            index = match
        }
        if value == 1 {
            guard !keys[index].held else { return false }
            keys[index].held = true; keys[index].pressed = true; keys[index].usage = usage; notice = nil
        } else {
            guard keys[index].held else { return false }
            keys[index].held = false; keys[index].released = true
        }
        if keys.allSatisfy({ $0.complete }) { phase = .complete }
        return true
    }
    mutating func skipCurrent() {
        guard guided, listening, let index = keys.firstIndex(where: { !$0.complete }), !keys[index].held else { return }
        keys[index].absent = true; notice = nil
        if keys.allSatisfy({ $0.complete }) { phase = .complete }
    }
    mutating func tick(now: TimeInterval) { if listening && now >= deadline { phase = .incomplete } }
    mutating func stop(_ reason: String) { if listening { phase = .stopped(reason) } }
    mutating func fail(_ reason: String) { phase = .stopped(reason) }
}

protocol NavigationProbeSource: AnyObject {
    func start(value: @escaping (UInt64, UInt32, UInt32, Int) -> Void, failed: @escaping (String) -> Void) throws
    func stop()
}

/// The physical source and time are injected so cleanup is tested without HID access.
final class NavigationProbeSession {
    private(set) var state = NavigationProbeState()
    private var source: NavigationProbeSource?
    private var generation: UInt64 = 0
    var changed: (() -> Void)?
    let now: () -> TimeInterval
    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) { self.now = now }
    func start(deviceID: UInt64, source: NavigationProbeSource, guided: Bool = false) {
        stop("Test restarted.")
        generation &+= 1
        let current = generation
        state.start(deviceID: deviceID, now: now(), guided: guided)
        guard state.listening else { changed?(); return }
        self.source = source
        do {
            try source.start(value: { [weak self] id, page, usage, value in
                guard let self, self.generation == current else { return }
                if self.state.receive(deviceID: id, page: page, usage: usage, value: value, now: self.now()) { self.publish() }
            }, failed: { [weak self] reason in
                guard let self, self.generation == current, self.state.listening else { return }
                self.state.fail(reason); self.publish()
            })
        } catch { state.fail(error.localizedDescription) }
        publish()
    }
    func tick() { state.tick(now: now()); publish() }
    func skipCurrent() { state.tick(now: now()); state.skipCurrent(); publish() }
    func reset() { stop("Setup stopped."); generation &+= 1; state = NavigationProbeState(); publish() }
    func markAllAbsent(deviceID: UInt64) {
        reset(); state.start(deviceID: deviceID, now: now(), guided: true)
        for _ in 0..<4 { state.skipCurrent() }
        publish()
    }
    func stop(_ reason: String) { state.stop(reason); publish() }
    private func publish() {
        if !state.listening { source?.stop(); source = nil }
        changed?()
    }
    deinit { source?.stop() }
}
