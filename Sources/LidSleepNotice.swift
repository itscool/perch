import AppKit

/// Captured before sleep, independently of the session that recovery may end.
struct LidSleepIncident: Codable, Equatable {
    var id = UUID()
    var began: Date
    var power: LidPower
    var protectionRequested: Bool?
    var woke: Date?

    static func capture(wanted: Bool, observation: LidObservation, active: Bool?, now: Date) -> Self? {
        guard wanted, observation.closed == true else { return nil }
        return Self(began: now, power: observation.power, protectionRequested: active)
    }
    func hasWakeEvidence(events: [LidActivityEntry]) -> Bool {
        if let woke { return woke >= began }
        let after = events.filter { $0.date >= began.addingTimeInterval(-2) }.sorted { $0.date < $1.date }
        guard let index = after.firstIndex(where: { $0.message == "macOS notification: system sleep is beginning." && abs($0.date.timeIntervalSince(began)) < 10 }) else { return false }
        let next = after.suffix(from: after.index(after: index)).first {
            $0.message.contains("wake completed") || $0.message.contains("sleep is beginning") || $0.message.contains("pending idle-sleep attempt was cancelled")
        }
        return next?.message.contains("wake completed") == true
    }
    func explanation(events: [LidActivityEntry]) -> String {
        // A previous sleep/wake or new session is an attribution boundary.
        // A nearby command is evidence of a request, never proof of causality.
        let before = events.filter { $0.date <= began && $0.date >= began.addingTimeInterval(-120) }.sorted { $0.date < $1.date }
        let boundary = before.lastIndex { $0.message.contains("wake completed") || $0.message == "Enable lid protection requested." }
        let recent = boundary.map { Array(before.suffix(from: before.index(after: $0))) } ?? before
        let expiry = recent.contains { $0.message.hasPrefix("Lid not opened and external power not restored within 60 seconds.") }
        let supervision = recent.contains { $0.message == "App heartbeat expired. Ending lid protection." || $0.message == "Independent watchdog confirmation was lost. Ending lid protection." || $0.message.hasPrefix("Independent recovery restored normal system sleep") }
        var detail = "macOS reported sleep and then wake while your saved lid choice was on. "
        if expiry { detail += "Before sleep, Perch recorded that the 60-second interval expired without the lid opening or external power being restored, and requested sleep." }
        else if supervision { detail += "Before sleep, Perch recorded lost supervision and ended lid protection. Normal system sleep was allowed again." }
        else if protectionRequested == false { detail += "Lid protection was already inactive when sleep began." }
        else if protectionRequested == true { detail += "Perch had requested lid protection, but macOS does not identify the cause of this sleep in these records." }
        else { detail += "The current lid session could not be confirmed when sleep began. These records do not establish the cause of sleep." }
        detail += power == .external ? " External power was connected when sleep began." : power == .battery ? " The Mac was on battery when sleep began." : " Power state was not confirmed when sleep began."
        let transitions = recent.filter { $0.message.hasPrefix("Plugged in after ") || $0.message.hasPrefix("Unplugged;") || $0.message.hasPrefix("Lid closed on battery.") }.suffix(3)
        for event in transitions { detail += "\n" + event.message }
        detail += "\n\nSleep does not clear your saved lid choice. Check Keep awake for current protection; use Resume lid protection if it has stopped. Lid activity shows the recorded sequence."
        return detail
    }
}

/// Menu-app observation only: never changes the preference, helper or power.
final class LidSleepNotice {
    static let key = "sleep.pendingLidNotice.v1"
    private let defaults: UserDefaults
    private let readEvents: () -> [LidActivityEntry]
    private var observers: [NSObjectProtocol] = []
    private var presenting = false
    var show: ((LidSleepIncident, String, @escaping () -> Void) -> Void)?
    init(defaults: UserDefaults = .standard, readEvents: @escaping () -> [LidActivityEntry] = { (try? LidActivityStore().read()) ?? [] }) {
        self.defaults = defaults; self.readEvents = readEvents
    }
    var pending: LidSleepIncident? {
        get {
            guard let data = defaults.data(forKey: Self.key), data.count < 4096 else { return nil }
            return try? JSONDecoder().decode(LidSleepIncident.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) { defaults.set(data, forKey: Self.key) }
            else { defaults.removeObject(forKey: Self.key) }
            // Persist before the process can be suspended or restarted.
            defaults.synchronize()
        }
    }
    func start() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.pending = .capture(wanted: UserDefaults.standard.bool(forKey: SleepMasterChange.lidPreferenceKey),
                observation: MacLidGuardHardware().observe(), active: LidGuardClient.shared.status.flatMap { $0.fresh ? $0.armed : nil }, now: Date())
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, var incident = self.pending else { return }
            incident.woke = Date(); self.pending = incident
            // Allow the journal writer and desktop to resume before presenting.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.deliver() }
        })
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.deliver() }
    }
    func deliver() {
        guard !presenting, let incident = pending else { return }
        guard Date().timeIntervalSince(incident.began) >= 0, Date().timeIntervalSince(incident.began) < LidActivityStore.lifetime else { pending = nil; return }
        presenting = true
        DispatchQueue.global(qos: .utility).async {
            let events = self.readEvents()
            DispatchQueue.main.async {
                guard self.pending?.id == incident.id else { self.presenting = false; return }
                // After a process restart, a will-sleep notification alone is
                // insufficient: require the same sleep interval's wake record.
                guard incident.hasWakeEvidence(events: events), let show = self.show else { self.presenting = false; return }
                show(incident, incident.explanation(events: events)) {
                    if self.pending?.id == incident.id { self.pending = nil }
                    self.presenting = false
                }
            }
        }
    }
    deinit { for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) } }
}
