import AppKit

// Privileged commands pause Settings while the administrator prompt is up,
// and automation refusals are explained in Perch's words.
AppleScript.beginAuthorization = { _ = NSApplication.shared; return SettingsWindow.shared.beginAuthorization() }
AppleScript.describeFailure = { LaunchAccessRecovery.automationFailure($0, code: $1) }

// Helper, worker and test roles never reach the menu app.
if let role = ProcessRole.parse(CommandLine.arguments) { role.run() }
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
