import AppKit

final class LidActivityPage {
    typealias Read = (@escaping (Result<[LidActivityEntry], Error>) -> Void) -> Void
    private let page: SettingsLogPage
    var view: NSView { page.view }
    var status: NSTextField { page.status }
    var text: NSTextView { page.text }
    private let read: Read
    private let helperStatus: () -> LidGuardStatus?
    private var entries: [LidActivityEntry] = []
    private var generation = UUID()
    private var pending = false
    private var live = true
    var timer: Timer? { SettingsWindow.shared.pollTimer(for: view) }
    private lazy var liveButton: SettingsActionButton = SettingsActionButton(title: "Live updates") { [weak self] in
        guard let self else { return }; self.live.toggle(); self.liveButton.state = self.live ? .on : .off
        if self.live { self.refresh() }
    }
    var copyText: String {
        "Perch lid activity — last 24 hours, up to 1,024 entries\nCommand results and macOS sleep/wake notifications are separate events.\n\n" + Self.formatted(entries)
    }
    static func formatted(_ entries: [LidActivityEntry]) -> String {
        let format = DateFormatter(); format.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS Z"
        return entries.reversed().map { "\(format.string(from: $0.date))  [\($0.source)]\n\($0.message)" }.joined(separator: "\n\n")
    }
    init(read: Read? = nil, helperStatus: @escaping () -> LidGuardStatus? = { LidGuardClient.shared.status }) {
        page = SettingsLogPage(placeholder: "Reading lid activity…", accessibilityLabel: "Lid activity entries, newest first")
        self.helperStatus = helperStatus
        self.read = read ?? { completion in
            guard !SettingsWindow.shared.testing else { completion(.success([])); return }
            DispatchQueue.global(qos: .utility).async {
                let result = Result { try LidActivityStore().read() }
                DispatchQueue.main.async { completion(result) }
            }
        }
        page.copy = { [weak self] in self?.copyText ?? "" }
        liveButton.setButtonType(.switch); liveButton.state = .on
        page.addControl(liveButton)
    }
    func show() {
        SettingsWindow.shared.show(.init(title: "Lid activity", detail: "Last 24 hours · up to 1,024 entries · newest first. Elapsed times begin when a change is observed. Sleep requests and macOS sleep/wake notifications appear separately. Pause Live updates or select text to read without movement.", view: view,
                                         leave: { [self] in stop() }, poll: .init(every: 1, whileBusy: true) { [weak self] in self?.refresh() }))
        refresh()
    }
    func stop() { generation = UUID(); pending = false }
    func refresh() {
        guard live, !pending, text.selectedRange().length == 0, SettingsWindow.shared.pages.last?.view === view else { return }
        pending = true; let request = generation
        read { [weak self] result in
            guard let self, self.generation == request else { return }; self.pending = false
            guard self.live, self.text.selectedRange().length == 0 else { return }
            let helper = self.helperStatus()
            let statusText: String, kind: SettingsFeedbackKind
            switch result {
            case .success(let entries):
                self.entries = LidActivityStore.retained(entries, now: Date())
                statusText = helper?.activityError ?? (helper?.fresh == true ? "\(self.entries.count) entries · \(helper!.armed ? "Lid protection active" : "Lid session off")" : "\(self.entries.count) saved entries · The lid helper is not currently confirmed. History may have gaps.")
                kind = helper?.fresh == true && helper?.activityError == nil ? .information : .warning
            case .failure(let error):
                self.entries = LidActivityStore.retained(self.entries, now: Date())
                statusText = "Activity unavailable: \(error.localizedDescription) Review Setup → Lid protection."; kind = .warning
            }
            self.page.present(self.entries.isEmpty ? "No recorded lid activity in the last 24 hours. The updated lid helper records changes while it is running, including when lid protection is off." : Self.formatted(self.entries),
                              empty: self.entries.isEmpty, status: statusText, kind: kind)
        }
    }
}

extension AppDelegate {
    @objc func lidActivity() { LidActivityPage().show() }
}
