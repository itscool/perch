import AppKit

final class LidActivityPage {
    typealias Read = (@escaping (Result<[LidActivityEntry], Error>) -> Void) -> Void
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 572, height: 490))
    let status = NSTextField(wrappingLabelWithString: "Reading lid activity…")
    let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 552, height: 408))
    private let scroll = NSScrollView(frame: NSRect(x: 0, y: 42, width: 572, height: 398))
    private let read: Read
    private let helperStatus: () -> LidGuardStatus?
    private var entries: [LidActivityEntry] = []
    private var generation = UUID()
    private var pending = false
    private var live = true
    private(set) var timer: Timer?
    private lazy var copyButton = SettingsActionButton(title: "Copy log") { [weak self] in
        guard let self else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(self.copyText, forType: .string)
    }
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
        self.helperStatus = helperStatus
        self.read = read ?? { completion in
            guard !SettingsWindow.shared.testing else { completion(.success([])); return }
            DispatchQueue.global(qos: .utility).async {
                let result = Result { try LidActivityStore().read() }
                DispatchQueue.main.async { completion(result) }
            }
        }
        status.font = .systemFont(ofSize: 12); status.frame = NSRect(x: 4, y: 448, width: 564, height: 40)
        text.isEditable = false; text.isSelectable = true
        text.font = .systemFont(ofSize: 12); text.textColor = .labelColor
        text.backgroundColor = .textBackgroundColor
        text.textContainerInset = NSSize(width: 10, height: 10)
        text.autoresizingMask = .width; text.isVerticallyResizable = true
        text.textContainer?.widthTracksTextView = true
        text.setAccessibilityLabel("Lid activity entries, newest first")
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = false; scroll.borderType = .bezelBorder; scroll.documentView = text
        copyButton.frame = NSRect(x: 0, y: 0, width: 120, height: 32)
        liveButton.setButtonType(.switch); liveButton.state = .on; liveButton.frame = NSRect(x: 398, y: 0, width: 174, height: 32)
        [status, scroll, copyButton, liveButton].forEach { view.addSubview($0) }
    }
    func show() {
        SettingsWindow.shared.show(.init(title: "Lid activity", detail: "Last 24 hours · up to 1,024 entries · newest first. Elapsed times begin when a change is observed. Sleep requests and macOS sleep/wake notifications appear separately. Pause Live updates or select text to read without movement.", view: view, leave: { [self] in stop() }))
        refresh()
        timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
    func stop() { timer?.invalidate(); timer = nil; generation = UUID(); pending = false }
    func refresh() {
        guard live, !pending, text.selectedRange().length == 0, SettingsWindow.shared.pages.last?.view === view else { return }
        pending = true; let request = generation
        read { [weak self] result in
            guard let self, self.generation == request else { return }; self.pending = false
            guard self.live, self.text.selectedRange().length == 0 else { return }
            let oldHeight = self.text.frame.height, offset = self.scroll.contentView.bounds.origin
            let helper = self.helperStatus()
            switch result {
            case .success(let entries):
                self.entries = LidActivityStore.retained(entries, now: Date())
                self.status.stringValue = helper?.activityError ?? (helper?.fresh == true ? "\(self.entries.count) entries · \(helper!.armed ? "Lid protection enabled" : "Lid protection off")" : "\(self.entries.count) saved entries · The lid helper is not currently confirmed. History may have gaps.")
                self.status.textColor = helper?.fresh == true && helper?.activityError == nil ? .secondaryLabelColor : StatusColors.warning
            case .failure(let error):
                self.entries = LidActivityStore.retained(self.entries, now: Date())
                self.status.stringValue = "Activity unavailable: \(error.localizedDescription) Review lid protection in Keep awake."
                self.status.textColor = StatusColors.warning
            }
            let content = self.entries.isEmpty ? "No recorded lid activity in the last 24 hours. The updated lid helper records changes while it is running, including when lid protection is off." : Self.formatted(self.entries)
            if self.text.string != content {
                self.text.string = content; self.text.layoutManager?.ensureLayout(for: self.text.textContainer!)
                if offset.y > 1 { self.scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, offset.y + self.text.frame.height - oldHeight))) }
                else { self.scroll.contentView.scroll(to: .zero) }
                self.scroll.reflectScrolledClipView(self.scroll.contentView)
            }
            self.copyButton.isEnabled = !self.entries.isEmpty
        }
    }
}

extension AppDelegate {
    @objc func lidActivity() { LidActivityPage().show() }
}
