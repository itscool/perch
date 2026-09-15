import AppKit

/// Nonpresenting tests: no menu tracking, window, input dispatch or helper access.
func runMenuTooltipTests() throws {
    func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw AppError(message: message) }
    }
    let menu = NSMenu()
    let panic = NSMenuItem(title: "Panic", action: nil, keyEquivalent: "")
    panic.toolTip = "Panic help"
    let panicRow = MenuRowView(item: panic, kind: .command)
    panic.view = panicRow; menu.addItem(panic)
    let other = NSMenuItem(title: "Other", action: nil, keyEquivalent: "")
    let otherRow = MenuRowView(item: other, kind: .command)
    other.view = otherRow; menu.addItem(other)
    try check(panic.toolTip == nil && panicRow.toolTip == "Panic help", "Native tooltip still owns custom row help")
    try check(other.toolTip == nil && otherRow.toolTip == nil, "Empty row inherited another command's help")
    other.menuHelp = "Other help"
    panic.menuHelp = "Updated panic help"
    try check(otherRow.toolTip == "Other help" && panicRow.toolTip == "Updated panic help", "Tooltip update crossed row ownership")
    let replacement = MenuRowView(item: other, kind: .toggle)
    other.view = replacement
    try check(replacement.toolTip == "Other help" && other.toolTip == nil, "Renderer replacement lost or duplicated help")
    replacement.shortcutHint = "⌃⌥K"
    try check(replacement.accessibilityHelp()?.contains("Other help") == true && replacement.accessibilityHelp()?.contains("⌃⌥K") == true, "Accessible row help or shortcut lost")
    let owner = NSObject()
    let foreign = NSTrackingArea(rect: replacement.bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: owner)
    replacement.addTrackingArea(foreign)
    for width in [430.0, 620.0, 430.0] {
        replacement.setFrameSize(NSSize(width: width, height: 24))
        replacement.updateTrackingAreas(); replacement.updateTrackingAreas()
        try check(replacement.trackingAreas.contains { $0 === foreign }, "Hover refresh removed another owner's tracking area")
        try check(replacement.trackingAreas.filter { ($0.owner as AnyObject?) === replacement }.count == 1, "Hover tracking duplicated across refresh")
    }
    other.isHidden = true; other.menuHelp = nil; other.isHidden = false
    try check(replacement.toolTip == nil && other.toolTip == nil, "Cleared help returned after hide/show")
    let native = NSMenuItem(title: "Native picker option", action: nil, keyEquivalent: "")
    native.menuHelp = "Native help"
    try check(native.toolTip == "Native help", "Native popup tooltip behavior changed")
    print("PASS: row-local help, empty/updated/cleared help, renderer replacement, accessibility and tracking ownership (no native hover replay)")
}
