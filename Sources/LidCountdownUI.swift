import AppKit
import SwiftUI
import Carbon

final class CountdownPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct CountdownShortcuts: Codable, Equatable {
    var increase = PanicShortcut(key: UInt32(kVK_ANSI_Equal), enabled: true)
    var decrease = PanicShortcut(key: UInt32(kVK_ANSI_Minus), enabled: true)
    static let storageKey = "sleep.countdown.shortcuts"
    static let keys = [("+", UInt32(kVK_ANSI_Equal)), ("−", UInt32(kVK_ANSI_Minus))] + PanicShortcut.keys
    static func title(_ shortcut: PanicShortcut) -> String {
        let modifiers = [(controlKey,"⌃"),(optionKey,"⌥"),(shiftKey,"⇧"),(cmdKey,"⌘")]
            .filter { shortcut.modifiers & UInt32($0.0) != 0 }.map(\.1).joined()
        return modifiers + (keys.first { $0.1 == shortcut.key }?.0 ?? "?")
    }
}

/// Two transactional Carbon registrations. Held-key repeats cannot add time.
final class CountdownHotKeys {
    private var handler: EventHandlerRef?
    private var registrations: [UInt32: EventHotKeyRef] = [:]
    private var installed: CountdownShortcuts?
    private var latch = CountdownKeyLatch()
    var action: ((Int) -> Void)?
    init() {
        var events = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                      EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                  id.signature == 0x50435444 else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<CountdownHotKeys>.fromOpaque(context).takeUnretainedValue()
            guard owner.registrations[id.id] != nil else { return OSStatus(eventNotHandledErr) }
            if GetEventKind(event) == UInt32(kEventHotKeyReleased) { owner.latch.release(id.id) }
            else if owner.latch.press(id.id) { owner.action?(id.id == 1 ? 1 : -1) }
            return noErr
        }, events.count, &events, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func register(_ value: CountdownShortcuts) throws {
        guard handler != nil else { throw AppError(message: "Countdown shortcut registration is unavailable.") }
        guard !value.increase.enabled || !value.decrease.enabled || value.increase.key != value.decrease.key || value.increase.modifiers != value.decrease.modifiers else {
            throw AppError(message: "Add and subtract need different shortcuts.")
        }
        var staged: [UInt32: EventHotKeyRef] = [:]
        do {
            for (id, shortcut, prior) in [(UInt32(1), value.increase, installed?.increase), (UInt32(2), value.decrease, installed?.decrease)] {
                guard shortcut.enabled, shortcut != prior || registrations[id] == nil else { continue }
                guard shortcut.modifiers != 0 else { throw AppError(message: "Choose at least one modifier for each countdown shortcut.") }
                var ref: EventHotKeyRef?
                let result = RegisterEventHotKey(shortcut.key, shortcut.modifiers, EventHotKeyID(signature: 0x50435444, id: id), GetApplicationEventTarget(), 0, &ref)
                guard result == noErr, let ref else { throw AppError(message: "\(CountdownShortcuts.title(shortcut)) is already in use or unavailable. Choose another shortcut. Your previous shortcuts are kept.") }
                staged[id] = ref
            }
        } catch { for ref in staged.values { UnregisterEventHotKey(ref) }; throw error }
        for (id, shortcut, prior) in [(UInt32(1), value.increase, installed?.increase), (UInt32(2), value.decrease, installed?.decrease)] {
            if !shortcut.enabled || shortcut != prior {
                if let old = registrations.removeValue(forKey: id) { UnregisterEventHotKey(old) }
            }
        }
        registrations.merge(staged) { _, new in new }; installed = value; latch.clear()
    }
    deinit { for ref in registrations.values { UnregisterEventHotKey(ref) }; if let handler { RemoveEventHandler(handler) } }
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
    private var hotKeys: CountdownHotKeys?
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
        if let data = UserDefaults.standard.data(forKey: CountdownShortcuts.storageKey), let saved = try? JSONDecoder().decode(CountdownShortcuts.self, from: data) { shortcuts = saved }
        if let data = UserDefaults.standard.data(forKey: Self.storageKey), var saved = try? JSONDecoder().decode(LidCountdown.self, from: data) {
            // The helper may replace this with an adopted live countdown. A
            // persisted UI record alone never grants or resumes protection.
            saved.finish(.interrupted, now: min(saved.deadline, LidGuardClock.now)); countdown = saved
        }
        dismissed = UserDefaults.standard.string(forKey: "sleep.countdown.dismissed").flatMap(UUID.init(uuidString:))
        let keys = CountdownHotKeys(); keys.action = { [weak self] in self?.adjust($0) }; hotKeys = keys
        do { try keys.register(shortcuts) } catch { shortcutError = error.localizedDescription }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
        refresh()
    }
    func saveShortcuts(_ value: CountdownShortcuts) {
        do {
            let data = try JSONEncoder().encode(value)
            try hotKeys?.register(value)
            if !fixture { UserDefaults.standard.set(data, forKey: CountdownShortcuts.storageKey) }
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
    private func persist() {
        if let value = countdown, let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: Self.storageKey) }
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
    func row(_ title: String, path: WritableKeyPath<CountdownShortcuts, PanicShortcut>) -> some View {
        let shortcut = model.shortcuts[keyPath: path]
        func edit(_ change: (inout PanicShortcut) -> Void) { var value = model.shortcuts; change(&value[keyPath: path]); model.saveShortcuts(value) }
        return VStack(alignment: .leading, spacing: 8) {
            Toggle(title, isOn: Binding(get: { shortcut.enabled }, set: { value in edit { $0.enabled = value } }))
            HStack {
                Picker("Key", selection: Binding(get: { shortcut.key }, set: { value in edit { $0.key = value } })) {
                    ForEach(CountdownShortcuts.keys, id: \.1) { Text($0.0).tag($0.1) }
                }.frame(width: 110)
                ForEach([(controlKey,"Ctrl"),(optionKey,"Opt"),(cmdKey,"Cmd"),(shiftKey,"Shift")], id: \.0) { flag, name in
                    Toggle(name, isOn: Binding(get: { shortcut.modifiers & UInt32(flag) != 0 }, set: { on in edit { if on { $0.modifiers |= UInt32(flag) } else { $0.modifiers &= ~UInt32(flag) } } }))
                }
            }
        }.padding(12).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            row("Add five minutes", path: \.increase)
            row("Subtract five minutes", path: \.decrease)
            Text("The + shortcut uses the +/= key; add Shift only if you want it in the shortcut. Changes save immediately. Held keys never repeat adjustments.").font(.callout).foregroundStyle(.secondary)
            if let error = model.shortcutError { Text(error).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
        }.padding(4)
    }
}

extension AppDelegate {
    @objc func countdownSettings() {
        let view = NSHostingView(rootView: CountdownShortcutSettings(model: .shared))
        view.frame = NSRect(x: 0, y: 0, width: 580, height: 240)
        SettingsWindow.shared.show(.init(title: "Countdown shortcuts", detail: "Start five minutes of temporary keep awake, including with the lid closed. Each press adds or subtracts five minutes, up to \(Int(LidCountdownLimits.maximum / 60)) minutes remaining. Opening the lid finishes it; connecting power does not change the time.", view: view))
    }
}
