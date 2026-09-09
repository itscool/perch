import AppKit

extension AppDelegate {
    @objc func navigationSettings() {
        let page = SettingsTaskPage(title: "Navigation keys", detail: "Change Home/End and Page Up/Down on external keyboards. Built-in Fn+arrows keep their normal behavior. Choices save immediately; unknown keyboard sources pass through unchanged.", height: 458)
        let home = page.add("Home/End move to line edges", detail: "Move to the start or end of the current line in supported apps.", checkbox: true) { [weak self] in self?.toggleHomeEnd() }
        let paging = page.add("Page Up/Down move the cursor", detail: "Move the text cursor by a page instead of only scrolling the view.", checkbox: true) { [weak self] in self?.togglePageKeys() }
        page.add("Learn or manage layouts…", detail: "Choose a keyboard. A learned layout saves automatically after the last key.") { [weak self] in self?.testNavigationKeys() }
        let setup = page.add("Review Accessibility…", detail: "Restore the helper or its access if navigation controls are unavailable.") { [weak self] in
            if HelperStatusIPC.inputClient.value?.fresh != true { self?.advancedSafetySettings() }
            else if HelperStatusIPC.inputClient.value?.trusted != true { self?.inputPermissionsFromSettings() }
            else { self?.inputPermissionsFromSettings() }
        }
        page.add("App exceptions…", detail: "Choose apps that keep their own navigation behavior. Browsers are excluded by default.") { [weak self] in self?.navigationExceptions() }
        page.update = { [weak self, weak page] in
            guard let self else { return }
            let preferences = SafetyConfiguration.load().navigation ?? NavigationPreferences()
            let input = HelperStatusIPC.inputClient.value
            let access = input?.fresh == true && input?.trusted == true
            let profiles = self.keyboardModes.registrations.compactMap { $0.profile }.filter { NavigationEventDevices.mapping($0) != nil }
            home.state = preferences.homeEnd ? .on : .off; paging.state = preferences.pageUpDown ? .on : .off
            // An enabled choice can always be turned off, even after losing a device or grant.
            home.isEnabled = preferences.homeEnd || (access && profiles.contains { $0.hasHomeEnd })
            paging.isEnabled = preferences.pageUpDown || (access && profiles.contains { $0.hasPageKeys })
            setup.title = input?.fresh != true ? "Review background helpers…" : !access ? "Set up Accessibility…" : "Review Accessibility…"
            page?.status.stringValue = input?.fresh != true ? "The input helper is unavailable. Restore it before checking access or enabling navigation." : !access ? "Perch Helper needs Accessibility. Restore access, then return here to choose behavior." : self.keyboardModes.registrationPending ? "Checking connected keyboards. Your saved behavior choices are kept." : self.keyboardModes.registrationError != nil ? "Keyboard detection needs attention. Review layouts to retry; your saved choices are kept." : self.keyboardModes.registrations.isEmpty ? "Connect an external keyboard to check its navigation keys. Known layouts are recognized automatically; your saved behavior choices are kept." : profiles.isEmpty ? "This keyboard needs a navigation layout. Open Learn or manage layouts to set it up; the layout saves automatically." : input?.navigationUnidentified == true ? "macOS did not identify the source keyboard. Unidentified keys keep their normal behavior; review the layout if needed." : "A supported external layout is available. Choose behavior above; app exceptions can keep individual apps unchanged."
        }
        page.show(delegate: self)
    }
    func refreshNavigationItems() {
        guard homeEndItem != nil else { return }
        let config = SafetyConfiguration.load()
        let preferences = config.navigation ?? NavigationPreferences()
        let helper = HelperStatusIPC.inputClient.value
        let available = helper?.fresh == true && helper?.trusted == true && helper?.navigationDevices != nil
        let profiles = keyboardModes.registrations.compactMap { $0.profile }
        for (item, enabled, capable) in [(homeEndItem!, preferences.homeEnd, profiles.contains { $0.hasHomeEnd && NavigationEventDevices.mapping($0) != nil }), (pageKeysItem!, preferences.pageUpDown, profiles.contains { $0.hasPageKeys && NavigationEventDevices.mapping($0) != nil })] {
            item.state = enabled ? .on : .off
            let checking = (helper == nil && HelperStatusIPC.inputClient.initiallyChecking) || keyboardModes.registrationPending
            item.isEnabled = enabled || !checking
            let needsSetup = !enabled && (!available || !capable)
            item.action = needsSetup ? #selector(keyboardSettings) : item === homeEndItem ? #selector(toggleHomeEnd) : #selector(togglePageKeys)
            (item.view as? MenuRowView)?.opensAnotherInterface = { needsSetup }
            let warning: String
            if checking { warning = "Checking input and keyboard…" }
            else if !available { warning = "⚠ Input setup · Settings" }
            else if !capable { warning = "⚠ Keyboard setup · Settings" }
            else if enabled && helper?.active != true { warning = "⚠ Input controls not running" }
            else if enabled && helper?.navigationUnidentified == true { warning = "⚠ Cannot identify keyboard" }
            else if enabled && helper?.navigationDevices == 0 { warning = "⚠ Checking keyboard source" }
            else { warning = "" }
            let hint = warning.isEmpty ? (enabled ? "On · app exceptions apply" : "Off") : warning
            label(item, item === homeEndItem ? "Home/End move to line edges" : "Page Up/Down move the cursor", hint: hint, hintColor: warning.hasPrefix("⚠") ? StatusColors.warning : .secondaryLabelColor)
            item.toolTip = "External keyboards only. Built-in Fn+arrows are unchanged. Unknown event sources pass through unchanged. App exceptions are in Settings → Keyboards → Navigation keys."
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
        showNavigationExceptions(load: { SafetyConfiguration.load().navigation ?? NavigationPreferences() }, save: { id, excluded in
            var latest = SafetyConfiguration.load()
            var navigation = latest.navigation ?? NavigationPreferences()
            navigation.excludedApps.removeAll { $0 == id }
            if excluded { navigation.excludedApps.append(id) }
            latest.navigation = navigation; try latest.save()
        })
    }
    func showNavigationExceptions(load: @escaping () -> NavigationPreferences, save: @escaping (String, Bool) throws -> Void) {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 572, height: 490))
        let current = load()
        let names = Dictionary(NavigationPreferences.defaultExceptions.map { ($0.1, $0.0) }, uniquingKeysWith: { first, _ in first })
        let all = Set(names.keys).union(current.excludedApps).sorted { (names[$0] ?? $0) < (names[$1] ?? $1) }
        let scroll = NSScrollView(frame: NSRect(x: 0,y: 70,width: 572,height: 420))
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = false; scroll.borderType = .bezelBorder
        let document = NSView(frame: NSRect(x: 0,y: 0,width: 546,height: CGFloat(all.count*29)))
        let status = NSTextField(wrappingLabelWithString: "Changes save automatically.")
        status.font = .systemFont(ofSize: 13); status.textColor = .secondaryLabelColor
        status.frame = NSRect(x: 8, y: 5, width: 556, height: 56); view.addSubview(status)
        for (index, id) in all.enumerated() {
            weak var checkbox: SettingsActionButton?
            let box = SettingsActionButton(title: names[id] ?? id) {
                guard let box = checkbox else { return }
                let previous = load().excludedApps.contains(id)
                do {
                    try save(id, box.state == .on)
                    status.stringValue = "✓ Saved automatically."
                    status.textColor = StatusColors.success
                } catch {
                    box.state = previous ? .on : .off
                    status.stringValue = "⚠ Not saved. " + error.localizedDescription + " Your previous choice was kept."
                    status.textColor = StatusColors.warning
                }
            }
            checkbox = box; box.setButtonType(.switch)
            box.state = current.excludedApps.contains(id) ? .on : .off
            box.frame = NSRect(x: 8,y: document.frame.height-CGFloat((index+1)*29),width: 525,height: 28)
            document.addSubview(box)
        }
        scroll.documentView = document; view.addSubview(scroll)
        scroll.contentView.scroll(to: NSPoint(x: 0,y: max(0,document.bounds.height-scroll.contentSize.height))); scroll.reflectScrolledClipView(scroll.contentView)
        SettingsWindow.shared.show(.init(title: "Navigation app exceptions", detail: "Checked apps keep their own Home/End and Page Up/Down behavior. Browsers are excluded because Command+arrow can navigate history outside a text field. Changes save automatically.", view: view))
    }
}
