import AppKit
import SwiftUI
import Carbon

final class CountdownPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The pair persists as `{increase, decrease}`; each is a Shortcut.
struct CountdownShortcuts: Codable, Equatable {
    var increase = Shortcut(key: UInt32(kVK_ANSI_Equal))
    var decrease = Shortcut(key: UInt32(kVK_ANSI_Minus))
    static let storageKey = "sleep.countdown.shortcuts"
}

final class LidCountdownController: ObservableObject {
    static let shared = LidCountdownController()
    @Published private(set) var countdown: LidCountdown?
    @Published private(set) var remaining = 0
    @Published private(set) var busy = false
    @Published private(set) var confirmed = false
    @Published private(set) var error: String?
    @Published private(set) var shortcutError: String?
    @Published private(set) var shortcuts = CountdownShortcuts()
    private let increaseHotKey = HotKey()
    private let decreaseHotKey = HotKey()
    private var timer: Timer?
    private var panel: NSPanel?
    private var dismissed: UUID?
    private static let storageKey = "sleep.countdown.last"
    private var observed: LidCountdown?
    private var queuedAdjustments: [Int] = []
    var openSetup: (() -> Void)?
    private let fixture: Bool
    private var fixtureTime: Double = 0
    private var now: Double { fixture ? fixtureTime : LidGuardClock.now }
    init(fixture: Bool = false) { self.fixture = fixture }
    func prepareFixture(finished: Bool) {
        guard fixture else { return }
        var value = LidCountdown(now: 0, closed: true, restoreSession: false)
        fixtureTime = 12
        if finished { value.observe(closed: false, now: fixtureTime) }
        countdown = value; confirmed = true; remaining = value.remaining(at: now)
    }
    func start() {
        guard !SettingsWindow.shared.testing, timer == nil else { return }
        if let saved = UserDefaults.standard.codable(CountdownShortcuts.self, forKey: CountdownShortcuts.storageKey) { shortcuts = saved }
        if var saved = UserDefaults.standard.codable(LidCountdown.self, forKey: Self.storageKey) {
            // The helper may replace this with an adopted live countdown. A
            // persisted UI record alone never grants or resumes protection.
            saved.finish(.interrupted, now: min(saved.deadline, LidGuardClock.now)); countdown = saved
        }
        dismissed = UserDefaults.standard.string(forKey: "sleep.countdown.dismissed").flatMap(UUID.init(uuidString:))
        increaseHotKey.action = { [weak self] in self?.adjust(1) }
        decreaseHotKey.action = { [weak self] in self?.adjust(-1) }
        do { try register(shortcuts) } catch { shortcutError = error.localizedDescription }
        let timer = MainTimer.every(0.25) { [weak self] in self?.refresh() }
        self.timer = timer
        refresh()
    }
    /// Both keys change together; a refused pair leaves the previous one active.
    private func register(_ value: CountdownShortcuts) throws {
        guard !value.increase.matches(value.decrease) else { throw PerchError("Add and subtract need different shortcuts.") }
        for shortcut in [value.increase, value.decrease] where shortcut.enabled {
            if let problem = ShortcutRegistry.perch.problem(with: shortcut, excluding: ShortcutRegistry.Source.countdown) { throw PerchError(problem) }
        }
        try HotKey.register([(increaseHotKey, value.increase), (decreaseHotKey, value.decrease)])
    }
    func saveShortcuts(_ value: CountdownShortcuts) {
        do {
            try register(value)
            if !fixture { try UserDefaults.standard.setCodable(value, forKey: CountdownShortcuts.storageKey) }
            shortcuts = value; shortcutError = nil
        } catch { shortcutError = error.localizedDescription }
    }
    func refresh() {
        guard !fixture else { return }
        if SettingsWindow.shared.interactionBusy { panel?.orderOut(nil) }
        let status = LidGuardClient.shared.status
        let fresh = status?.fresh == true
        let nextConfirmed = fresh && status?.armed == true && status?.error == nil
        if confirmed != nextConfirmed { confirmed = nextConfirmed }
        if fresh, let value = status?.countdown {
            if observed != value { observed = value; countdown = value; persist() }
        } else if fresh, countdown?.active == true {
            countdown?.finish(.interrupted, now: LidGuardClock.now); persist()
        }
        if let value = countdown {
            let nextRemaining = value.remaining(at: now)
            if remaining != nextRemaining { remaining = nextRemaining }
            if dismissed != value.id && panel?.isVisible != true { show() }
        }
    }
    private func persist() { Self.save(countdown, to: .standard) }
    /// Save the countdown so a relaunch can restore it. A countdown that cannot
    /// be encoded clears the saved one instead of leaving stale state to restore.
    static func save(_ value: LidCountdown?, to defaults: UserDefaults) {
        guard let value else { return }
        do { try defaults.setCodable(value, forKey: storageKey) } catch { defaults.removeObject(forKey: storageKey) }
    }
    func adjust(_ direction: Int) {
        if busy { queuedAdjustments.append(direction); return }
        if direction < 0 && countdown?.active != true { return }
        if fixture {
            if direction == 0 { countdown?.finish(.cancelled, now: now) }
            else if countdown?.active == true { countdown?.adjust(direction, now: now) }
            else if direction > 0 { countdown = LidCountdown(now: now, closed: false, restoreSession: false) }
            remaining = countdown?.remaining(at: now) ?? 0; return
        }
        guard LidGuardClient.shared.status?.fresh == true, !LidHelperUpdate.shared.state.pending else {
            error = "Finish Setup → Lid protection before starting a countdown."; show(); return
        }
        busy = true; error = nil; dismissed = nil; show()
        LidGuardClient.shared.adjustCountdown(direction) { [weak self] result in
            guard let self else { return }; self.busy = false
            if case .failure(let error) = result { self.error = error.localizedDescription; self.queuedAdjustments.removeAll() }
            self.refresh()
            if !self.queuedAdjustments.isEmpty { self.adjust(self.queuedAdjustments.removeFirst()) }
        }
    }
    func close() {
        guard countdown?.active != true else { adjust(0); return }
        dismissed = countdown?.id; panel?.orderOut(nil)
        if !fixture { UserDefaults.standard.set(dismissed?.uuidString, forKey: "sleep.countdown.dismissed") }
    }
    func show() {
        guard !SettingsWindow.shared.testing || fixture else { return }
        if panel == nil {
            let panel = CountdownPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 280), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "Perch countdown"; panel.level = .floating; panel.isFloatingPanel = true
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
            panel.isMovableByWindowBackground = true; panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: LidCountdownOverlay(model: self)); panel.center(); self.panel = panel
        }
        if !SettingsWindow.shared.interactionBusy {
            if fixture { panel?.makeKeyAndOrderFront(nil) } else { panel?.orderFrontRegardless() }
        }
    }
}

struct LidCountdownOverlay: View {
    @ObservedObject var model: LidCountdownController
    private var active: Bool { model.countdown?.active == true }
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 7) {
                Image(systemName: "bird.fill").foregroundStyle(.indigo)
                Text("Perch").fontWeight(.semibold)
                Spacer()
                Text(active ? "Keep awake" : model.countdown == nil ? "Countdown" : "Finished").foregroundStyle(.secondary)
            }
            Rectangle().fill(Color.indigo.opacity(0.65)).frame(height: 2)
            Text(LidCountdown.clockText(model.remaining)).font(.system(size: 48, weight: .medium, design: .rounded).monospacedDigit())
                .accessibilityLabel("\(model.remaining / 60) minutes, \(model.remaining % 60) seconds remaining")
            Text(model.busy ? "Confirming change…" : model.error ?? (active ? (model.confirmed ? "Opening the lid finishes the countdown." : "Protection is not confirmed. Checking the helper…") : model.countdown?.end == .opened ? "Lid opened. Time remaining is saved here." : model.countdown?.end == .interrupted ? "Protection stopped. Review Lid activity." : "Your usual sleep settings apply."))
                .font(.caption).foregroundStyle(model.error != nil || (active && !model.confirmed) ? Color.orange : Color.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if model.error != nil { Button("Review lid protection") { model.openSetup?() }.buttonStyle(.link) }
            HStack {
                Button("−5 min") { model.adjust(-1) }.disabled(!active || model.busy)
                Button("+5 min") { model.adjust(1) }.disabled(model.busy || (active && model.remaining >= Int(LidCountdownLimits.maximum)))
                Spacer()
                Button(active ? "Cancel" : "Close", systemImage: active ? "stop" : "xmark") { model.close() }.disabled(model.busy)
            }.buttonStyle(.bordered).controlSize(.small)
            if active && model.remaining > Int(LidCountdownLimits.step) {
                Text("Keep your Mac ventilated with the lid closed.").font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(20).frame(width: 320).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.indigo.opacity(0.22), lineWidth: 1))
    }
}

struct CountdownShortcutSettings: View {
    @ObservedObject var model: LidCountdownController
    func row(_ title: String, path: WritableKeyPath<CountdownShortcuts, Shortcut>) -> some View {
        let shortcut = model.shortcuts[keyPath: path]
        func edit(_ change: (inout Shortcut) -> Void) { var value = model.shortcuts; change(&value[keyPath: path]); model.saveShortcuts(value) }
        return SettingsShortcutEditor(title: title,
            enabled: Binding(get: { shortcut.enabled }, set: { value in edit { $0.enabled = value } }),
            key: Binding(get: { shortcut.key }, set: { value in edit { $0.key = value } }), choices: ShortcutKey.countdown,
            modifiers: Binding(get: { shortcut.modifiers }, set: { value in edit { $0.modifiers = value } }))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                row("Add five minutes", path: \.increase).frame(maxWidth: .infinity, alignment: .leading)
                row("Subtract five minutes", path: \.decrease).frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("The + shortcut uses the +/= key; add Shift only if you want it in the shortcut. Changes save immediately. Held keys never repeat adjustments.").font(.callout).foregroundStyle(.secondary)
            SettingsFeedback(text: model.shortcutError)
        }.padding(4)
    }
}

extension AppDelegate {
    @objc func countdownSettings() { hotkeySettings() }
}
