import AppKit

extension AppDelegate {
    func refreshNavigationItems() {
        guard homeEndItem != nil else { return }
        let config = SafetyConfiguration.load()
        let preferences = config.navigation ?? NavigationPreferences()
        let helper = HelperStatusIPC.inputClient.value
        let available = helper?.fresh == true && helper?.trusted == true && helper?.navigationDevices != nil
        let profiles = keyboardModes.registrations.compactMap { $0.profile }
        for (item, enabled, capable) in [(homeEndItem!, preferences.homeEnd, profiles.contains { $0.hasHomeEnd && NavigationEventDevices.mapping($0) != nil }), (pageKeysItem!, preferences.pageUpDown, profiles.contains { $0.hasPageKeys && NavigationEventDevices.mapping($0) != nil })] {
            item.state = enabled ? .on : .off
            item.isEnabled = enabled || (available && capable && !keyboardModes.registrationNeedsSetup)
            let warning: String
            if !available { warning = "⚠ Input setup · Settings" }
            else if keyboardModes.registrationNeedsSetup { warning = "⚠ Keyboard setup · Settings" }
            else if !capable { warning = "No supported keys" }
            else if enabled && helper?.active != true { warning = "⚠ Input controls not running" }
            else if enabled && helper?.navigationUnidentified == true { warning = "⚠ Cannot identify keyboard" }
            else if enabled && helper?.navigationDevices == 0 { warning = "⚠ Checking keyboard source" }
            else { warning = "" }
            let hint = warning.isEmpty ? (enabled ? "On · app exceptions apply" : "Off") : warning
            label(item, item === homeEndItem ? "Home/End move to line edges" : "Page Up/Down move the cursor", hint: hint, hintColor: warning.hasPrefix("⚠") ? StatusColors.warning : .secondaryLabelColor)
            item.toolTip = "External keyboards only. Built-in Fn+arrows are unchanged. Unknown event sources pass through unchanged. App exceptions are in Settings → Keyboard settings."
        }
        refreshExternalKeyboardSection()
    }
    func navigationProfilesForHelper() throws -> [NavigationKeyboardProfile] {
        var profiles = try KeyboardNavigationProfiles.read()
        for profile in keyboardModes.registrations.compactMap({ $0.profile }) {
            profiles.removeAll { $0.identity == profile.identity }; profiles.append(profile)
        }
        return profiles
    }
    func synchronizeNavigationProfiles() {
        guard keyboardModes.started, !keyboardModes.working else { return }
        do {
            var config = SafetyConfiguration.load()
            guard config.navigation?.enabled == true else { return }
            let profiles = try navigationProfilesForHelper()
            if profiles != config.navigationProfiles { config.navigationProfiles = profiles; try config.save() }
        } catch { keyboardModes.registrationError = error.localizedDescription }
    }
    func setNavigation(homeEnd: Bool) {
        do {
            var config = SafetyConfiguration.load()
            var preferences = config.navigation ?? NavigationPreferences()
            if homeEnd { preferences.homeEnd.toggle() } else { preferences.pageUpDown.toggle() }
            config.navigation = preferences
            config.navigationProfiles = try navigationProfilesForHelper()
            try config.save()
        } catch { showError(error) }
        refreshNavigationItems()
    }
    @objc func toggleHomeEnd() { setNavigation(homeEnd: true) }
    @objc func togglePageKeys() { setNavigation(homeEnd: false) }
    @objc func navigationExceptions() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 572, height: 490))
        let config = SafetyConfiguration.load()
        let current = config.navigation ?? NavigationPreferences()
        let names = Dictionary(NavigationPreferences.defaultExceptions.map { ($0.1, $0.0) }, uniquingKeysWith: { first, _ in first })
        let all = Set(names.keys).union(current.excludedApps).sorted { (names[$0] ?? $0) < (names[$1] ?? $1) }
        let scroll = NSScrollView(frame: NSRect(x: 0,y: 70,width: 572,height: 420))
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = false; scroll.borderType = .bezelBorder
        let document = NSView(frame: NSRect(x: 0,y: 0,width: 546,height: CGFloat(all.count*29)))
        var boxes: [NSButton] = []
        for (index, id) in all.enumerated() {
            let box = NSButton(checkboxWithTitle: names[id] ?? id, target: nil, action: nil)
            box.state = current.excludedApps.contains(id) ? .on : .off
            box.frame = NSRect(x: 8,y: document.frame.height-CGFloat((index+1)*29),width: 525,height: 28)
            document.addSubview(box); boxes.append(box)
        }
        scroll.documentView = document; view.addSubview(scroll)
        scroll.contentView.scroll(to: NSPoint(x: 0,y: max(0,document.bounds.height-scroll.contentSize.height))); scroll.reflectScrolledClipView(scroll.contentView)
        let save = SettingsActionButton(title: "Save exceptions") { [weak self] in
            do {
                var latest = SafetyConfiguration.load()
                var navigation = latest.navigation ?? NavigationPreferences()
                navigation.excludedApps = zip(all, boxes).filter { $0.1.state == .on }.map { $0.0 }
                latest.navigation = navigation; try latest.save()
                SettingsWindow.shared.goBack()
            } catch { self?.showError(error) }
        }
        save.frame = NSRect(x: 320,y: 10,width: 250,height: 32); view.addSubview(save)
        SettingsWindow.shared.show(.init(title: "Navigation app exceptions", detail: "Checked apps keep their own Home/End and Page Up/Down behavior. Browsers are excluded because Command+arrow can navigate history outside a text field. The two navigation switches are in Perch’s menu.", view: view))
    }
}
