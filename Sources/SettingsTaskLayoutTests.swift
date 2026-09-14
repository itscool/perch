import AppKit

/// No window, live state, or action dispatch. Hit testing exercises the native
/// ancestor bounds that performClick bypasses.
func runSettingsTaskLayoutTests() throws {
    for count in 1...20 {
        let page = SettingsTaskPage(title: "Layout fixture", detail: "", height: 498, statusHeight: 100)
        let parent = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 3000))
        parent.addSubview(page.view)
        var buttons: [NSButton] = []
        for index in 0..<count {
            buttons.append(page.add("Action \(index)", detail: "Explanation", action: {}))
        }
        page.status.stringValue = "Ready"
        page.arrangeRows(hiding: [])
        let compactHeight = page.view.frame.height
        page.status.stringValue = String(repeating: "An actionable failure with details that must wrap. ", count: 30)
        page.arrangeRows(hiding: [])
        guard page.view.frame.height > compactHeight,
              page.status.frame.height >= page.status.measuredHeight(width: page.status.frame.width) else {
            throw AppError(message: "Shared task feedback did not expand for the error")
        }
        page.status.stringValue = "Ready"; page.arrangeRows(hiding: [])
        guard page.view.frame.height == compactHeight else { throw AppError(message: "Shared task feedback retained an empty error area") }
        for button in buttons {
            guard page.view.bounds.contains(button.frame) else { throw AppError(message: "A task button exceeds its document bounds") }
            let point = parent.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), from: button)
            guard let hit = parent.hitTest(point), hit === button || hit.isDescendant(of: button) else {
                throw AppError(message: "A visible task button cannot be hit through its ancestors")
            }
        }
        for child in page.view.subviews {
            guard page.view.bounds.contains(child.frame) else { throw AppError(message: "A task explanation exceeds its document bounds") }
        }
    }
    print("PASS: 210 native task-row hit targets and their explanations stay within document bounds; no windows or action dispatch")
}
