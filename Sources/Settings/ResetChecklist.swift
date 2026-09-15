import AppKit
import ServiceManagement

/// Scope and consequences are visible before opening a confirmation.
enum ResetArea: String, CaseIterable, Hashable {
    case preferences, layouts, appearance, sleep, audio, privacy
    var title: String {
        switch self {
        case .preferences: return "Perch preferences & agents"
        case .layouts: return "Learned keyboard layouts"
        case .appearance: return "Menu appearance"
        case .sleep: return "Perch sleep protection"
        case .audio: return "System audio"
        case .privacy: return "Perch privacy permissions"
        }
    }
    var detail: String {
        switch self {
        case .preferences: return "Reset saved feature choices, keyboard modes and agents. Ends Perch’s protection and quits the app. Learned layouts, appearance and shared Desk setup are kept."
        case .layouts: return "Forget a learned navigation layout or all saved layouts, including disconnected keyboards. Bundled defaults, Fn and modifier choices stay available."
        case .appearance: return "Restore Perch original for light and dark menus, including System. Saved appearance presets and other preferences are kept."
        case .sleep: return "End Perch’s lid protection and keep-awake request, and clear those choices. Other apps’ assertions and unowned sleep overrides are kept."
        case .audio: return "Unmute macOS system audio. Volume and other sound settings are kept."
        case .privacy: return "Forget macOS permission decisions for Perch and its helpers. Other apps are excluded; Perch may need access granted again in Setup."
        }
    }
}
struct ResetChecklistPlan {
    var areas: Set<ResetArea>
    var keyboard: NavigationKeyboardIdentity? = nil // nil explicitly means all layouts.
    var ordered: [ResetArea] {
        [.layouts, .appearance, .audio, .sleep, .privacy, .preferences].filter {
            areas.contains($0) && !($0 == .sleep && areas.contains(.preferences))
        }
    }
    var summary: String {
        ordered.map { area in
            let scope = area == .layouts ? (keyboard.map { "\($0.name) · \($0.transport)" } ?? "all saved layouts") : area.detail
            return "• \(area.title): \(scope)"
        }.joined(separator: "\n\n") + "\n\n" + (areas.contains(.preferences)
            ? "Perch quits only after all selected resets succeed. Its helpers stop; reopen Perch afterward to restore them."
            : "Perch stays open. Unselected areas are kept.")
    }
}

/// Owns execution after leaving a page. Completed areas are never repeated by Retry.
final class ResetBatchOperation {
    static let shared = ResetBatchOperation(execute: ResetBatchExecutor.execute, quit: { NSApp.terminate(nil) })
    private(set) var running = false
    private(set) var results: [ResetArea: Result<String, Error>] = [:]
    private(set) var plan: ResetChecklistPlan?
    private(set) var generation = UUID()
    private let execute: (ResetArea, ResetChecklistPlan, @escaping (Result<String, Error>) -> Void) -> Void
    private let quit: () -> Void
    init(execute: @escaping (ResetArea, ResetChecklistPlan, @escaping (Result<String, Error>) -> Void) -> Void, quit: @escaping () -> Void = {}) {
        self.execute = execute; self.quit = quit
    }
    var failedPlan: ResetChecklistPlan? {
        guard !running, let plan else { return nil }
        let failed = Set(results.compactMap { area, result -> ResetArea? in if case .failure = result { return area }; return nil })
        return failed.isEmpty ? nil : ResetChecklistPlan(areas: failed, keyboard: plan.keyboard)
    }
    func start(_ plan: ResetChecklistPlan, retry: Bool = false) {
        guard !running, !plan.areas.isEmpty else { return }
        if !retry { results = [:]; self.plan = plan }
        generation = UUID(); let token = generation
        running = true
        func step(_ remaining: ArraySlice<ResetArea>) {
            guard self.running, self.generation == token else { return }
            guard let area = remaining.first else {
                self.running = false
                if self.plan?.areas.contains(.preferences) == true, self.failedPlan == nil { self.quit() }
                return
            }
            if area == .preferences, self.results.values.contains(where: { if case .failure = $0 { return true }; return false }) {
                self.results[area] = .failure(AppError(message: "Not reset because another selected area failed. Perch stays open so you can retry."))
                step(remaining.dropFirst()); return
            }
            var completed = false
            self.execute(area, plan) { result in
                guard !completed, self.running, self.generation == token else { return }
                completed = true; self.results[area] = result
                step(remaining.dropFirst())
            }
        }
        // Remove only retried failures; retain previous successes for the result and quit decision.
        if retry { for area in plan.ordered { results.removeValue(forKey: area) } }
        step(plan.ordered[...])
    }
}
enum ResetBatchExecutor {
    static func execute(_ area: ResetArea, _ plan: ResetChecklistPlan, completion: @escaping (Result<String, Error>) -> Void) {
        guard !SettingsWindow.shared.testing else { completion(.failure(AppError(message: "Live reset is disabled in UI tests."))); return }
        if area == .privacy {
            guard PrivacyOnlyReset.operation.run(global: false, completion: completion) else {
                completion(.failure(AppError(message: "Another privacy reset is running. Wait for it, then retry."))); return
            }
            return
        }
        do {
            switch area {
            case .layouts: try KeyboardNavigationProfiles.reset(plan.keyboard)
            case .appearance:
                MenuAppearanceStore.shared.save(MenuAppearance(), restoring: true)
                if let error = MenuAppearanceStore.shared.problem { throw AppError(message: error) }
            case .audio:
                _ = try AppleScript.run("set volume output muted false")
                guard try !AudioStatus.muted() else { throw AppError(message: "Audio is still muted.") }
            case .sleep:
                try LidGuardInstall.cleanup()
                var config = SafetyConfiguration.load(); config.keepAwake = false; try config.save()
                UserDefaults.standard.removeObject(forKey: SleepPreferences.lidPreferenceKey)
            case .preferences:
                do {
                    try SettingsReset.stopHelpers()
                    if SMAppService.mainApp.status != .notRegistered { try SMAppService.mainApp.unregister() }
                    try SettingsReset.clear(.init(sections: ["preferences"]), defaults: .standard,
                        domain: Bundle.main.bundleIdentifier ?? "local.scott.perch", base: SafetyFiles.base,
                        preserving: [MenuAppearanceStore.key, MenuAppearanceStore.presetsKey, SettingsWindow.sizeKey])
                } catch { throw AppError(message: error.localizedDescription + " Some helpers may be stopped; reopen Perch to restore them.") }
            case .privacy: break
            }
            completion(.success("Completed"))
        } catch { completion(.failure(error)) }
    }
}

final class ResetChecklistPage {
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 572, height: 640))
    private(set) var boxes: [ResetArea: NSButton] = [:]
    private var rows: [ResetArea: NSView] = [:]
    private var descriptions: [ResetArea: NSTextField] = [:]
    private var selected: Set<ResetArea> = []
    let keyboardPicker = SettingsActionPopup(frame: .zero, pullsDown: false)
    private var resetAction: SettingsActionButton!
    private var retry: SettingsActionButton!
    private var allApps: SettingsActionButton!
    private let broader = NSTextField(wrappingLabelWithString: "Affects other software: reset permission decisions for every app in your macOS account.")
    let status = SettingsStatusField(wrappingLabelWithString: "")
    private let operation: ResetBatchOperation
    private let readLayouts: () throws -> [NavigationKeyboardProfile]
    private var layouts: [NavigationKeyboardProfile] = []
    private let highlight: ResetArea?
    private var highlightedOnShow = false
    private var lastCompletion: UUID?
    init(highlight: ResetArea?, operation: ResetBatchOperation, readLayouts: @escaping () throws -> [NavigationKeyboardProfile], allApps: @escaping () -> Void) {
        self.highlight = highlight; self.operation = operation; self.readLayouts = readLayouts
        for area in ResetArea.allCases {
            let row = NSView(); row.identifier = .init("reset.row." + area.rawValue); row.wantsLayer = true; row.layer?.cornerRadius = 6
            if area == highlight { row.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.10).cgColor; row.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.55).cgColor; row.layer?.borderWidth = 1 }
            let box = SettingsActionButton(title: area.title) { [weak self] in
                guard let self, !self.operation.running else { return }
                if self.boxes[area]?.state == .on { self.selected.insert(area) } else { self.selected.remove(area) }
                self.refresh(); self.relayout()
            }
            box.setButtonType(.switch); box.identifier = .init("reset.area." + area.rawValue)
            box.toolTip = area.detail + (area == highlight ? " Highlighted from the page you came from; not selected automatically." : "")
            let text = NSTextField(wrappingLabelWithString: area.detail); text.font = .systemFont(ofSize: 12); text.textColor = .secondaryLabelColor
            row.addSubview(box); row.addSubview(text); view.addSubview(row)
            rows[area] = row; boxes[area] = box; descriptions[area] = text
        }
        keyboardPicker.setAccessibilityLabel("Saved keyboard layout to reset")
        keyboardPicker.identifier = .init("reset.keyboard")
        keyboardPicker.callback = { [weak self] in self?.refresh() }
        rows[.layouts]!.addSubview(keyboardPicker)
        reloadLayouts()
        resetAction = SettingsActionButton(title: "Reset selected…") { [weak self] in self?.confirm(retry: false) }
        resetAction.identifier = .init("reset.selected")
        retry = SettingsActionButton(title: "Retry failed resets…") { [weak self] in self?.confirm(retry: true) }
        retry.identifier = .init("reset.retry")
        self.allApps = SettingsActionButton(title: "All apps’ privacy permissions…", action: allApps)
        self.allApps.identifier = .init("reset.all-apps")
        status.identifier = .init("reset.results"); status.font = .systemFont(ofSize: 12)
        broader.font = .systemFont(ofSize: 12); broader.textColor = .secondaryLabelColor
        [resetAction!, retry!, status, self.allApps!, broader].forEach { view.addSubview($0) }
        refresh(); layout(NSSize(width: 572, height: 640))
    }
    func reloadLayouts() {
        keyboardPicker.removeAllItems(); keyboardPicker.addItems(withTitles: ["Choose keyboards…", "All saved layouts"])
        do { layouts = try readLayouts(); for item in layouts { keyboardPicker.addItem(withTitle: "\(item.identity.name) · \(item.identity.transport) · \(item.identity.vendor):\(item.identity.product)") } }
        catch { layouts = []; descriptions[.layouts]?.stringValue = "Saved layouts could not be read. Choose All saved layouts to clear unreadable data. Bundled defaults are kept." }
    }
    var proposedPlan: ResetChecklistPlan? {
        guard !selected.isEmpty else { return nil }
        var identity: NavigationKeyboardIdentity?
        if selected.contains(.layouts) {
            let index = keyboardPicker.indexOfSelectedItem
            guard index > 0, index == 1 || layouts.indices.contains(index - 2) else { return nil }
            identity = index == 1 ? nil : layouts[index - 2].identity
        }
        return ResetChecklistPlan(areas: selected, keyboard: identity)
    }
    private func confirm(retry: Bool) {
        guard !operation.running, let plan = retry ? operation.failedPlan : proposedPlan else { return }
        let alert = NSAlert(); alert.messageText = retry ? "Retry these failed resets?" : "Reset these selected areas?"
        alert.informativeText = plan.summary
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: plan.areas.contains(.preferences) ? "Reset selected & quit" : "Reset selected")
        SettingsWindow.shared.present(alert) { [weak self] response in
            guard response == .alertSecondButtonReturn, let self else { return }
            self.operation.start(plan, retry: retry); self.refresh(); self.relayout()
        }
    }
    func refresh() {
        if !operation.running, lastCompletion != operation.generation, operation.plan != nil {
            lastCompletion = operation.generation
            for (area, result) in operation.results { if case .success = result { selected.remove(area) } }
            if case .success? = operation.results[.layouts] { reloadLayouts() }
        }
        for area in ResetArea.allCases {
            boxes[area]?.state = selected.contains(area) ? .on : .off
            boxes[area]?.isEnabled = !operation.running && !(area == .sleep && selected.contains(.preferences))
        }
        descriptions[.sleep]?.stringValue = selected.contains(.preferences) ? "Included in the preferences reset: Perch must end its protection before quitting. Other apps’ sleep assertions are kept." : ResetArea.sleep.detail
        keyboardPicker.isHidden = !selected.contains(.layouts); keyboardPicker.isEnabled = !operation.running
        resetAction?.isEnabled = !operation.running && proposedPlan != nil
        resetAction?.title = operation.running ? "Reset in progress…" : "Reset selected…"
        retry?.isHidden = operation.failedPlan == nil; retry?.isEnabled = !operation.running
        allApps?.isEnabled = !operation.running
        let entries = ResetArea.allCases.compactMap { area -> String? in
            guard let result = operation.results[area] else { return nil }
            switch result { case .success: return "✓ \(area.title): completed"; case .failure(let error): return "⚠ \(area.title): \(error.localizedDescription)" }
        }
        status.stringValue = (operation.running ? "Resetting selected areas. You may leave; the operation continues.\n" : "") + entries.joined(separator: "\n")
        status.textColor = operation.failedPlan == nil ? .secondaryLabelColor : StatusColors.warning
    }
    func show() {
        SettingsWindow.shared.show(.init(title: "Reset Settings", detail: "Choose the areas to reset. Checkboxes only define your selection; nothing changes until you confirm Reset selected. All-app privacy is a separate action below.", view: view, refresh: { [weak self] in self?.refresh(); self?.relayout() }, layout: { [weak self] size in self?.layout(size) },
                                         poll: .init(every: 0.5) { [weak self] in
                                             guard let self else { return }
                                             let before = self.status.stringValue; self.refresh()
                                             if before != self.status.stringValue { self.relayout() }
                                         }))
        if let highlight, let row = rows[highlight], !highlightedOnShow { row.scrollToVisible(row.bounds); highlightedOnShow = true }
    }
    private func relayout() {
        guard let page = SettingsWindow.shared.pages.last, page.view === view, !SettingsWindow.shared.interactionBusy else { return }
        SettingsWindow.shared.display(page)
    }
    func layout(_ size: NSSize) {
        let width = size.width
        var heights: [ResetArea: CGFloat] = [:]
        for area in ResetArea.allCases {
            let text = descriptions[area]!
            let textHeight = ceil(text.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width-44, height: 10000)).height ?? 36)
            heights[area] = 38 + max(30, textHeight) + (area == .layouts && !keyboardPicker.isHidden ? 38 : 0)
        }
        let statusHeight = status.stringValue.isEmpty ? 0 : max(30, ceil(status.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width-16, height: 10000)).height ?? 30)) + 10
        let retryHeight: CGFloat = retry.isHidden ? 0 : 38
        let height = heights.values.reduce(0,+) + CGFloat(heights.count)*6 + 136 + statusHeight + retryHeight
        view.setFrameSize(NSSize(width: width, height: height))
        var y = height
        for area in ResetArea.allCases {
            let h = heights[area]!, row = rows[area]!
            y -= h
            row.frame = NSRect(x: 0, y: y, width: width, height: h)
            boxes[area]!.frame = NSRect(x: 8, y: h-30, width: width-16, height: 26)
            let extra: CGFloat = area == .layouts && !keyboardPicker.isHidden ? 38 : 0
            descriptions[area]!.frame = NSRect(x: 28, y: 8+extra, width: width-44, height: h-38-extra)
            if area == .layouts { keyboardPicker.frame = NSRect(x: 28, y: 6, width: width-44, height: 30) }
            y -= 6
        }
        resetAction.frame = NSRect(x: 0, y: y-34, width: width, height: 32); y -= 42
        retry.frame = NSRect(x: 0, y: y-32, width: width, height: 32); y -= retryHeight
        status.frame = NSRect(x: 8, y: y-statusHeight, width: width-16, height: statusHeight); y -= statusHeight+12
        allApps.frame = NSRect(x: 0, y: y-32, width: width, height: 32); y -= 38
        broader.frame = NSRect(x: 8, y: y-34, width: width-16, height: 34)
    }
}
