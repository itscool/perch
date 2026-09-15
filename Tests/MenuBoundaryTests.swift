import AppKit

private final class MenuBoundaryTarget: NSObject {
    var presses = 0
    @objc func first(_ sender: Any?) { presses += 1 }
    @objc func second(_ sender: Any?) { presses += 10 }
}

func runMenuBoundaryTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    func drainCommands() throws {
        var finished = false
        DispatchQueue.main.async { finished = true }
        let deadline = Date().addingTimeInterval(1)
        while !finished && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        try check(finished, "Deferred action queue did not drain within its bound")
    }
    let app = AppDelegate(), target = MenuBoundaryTarget()
    func row(_ title: String) -> MenuRowView {
        let item = NSMenuItem(title: title, action: #selector(MenuBoundaryTarget.first(_:)), keyEquivalent: "")
        item.target = target
        let view = MenuRowView(item: item, kind: .toggle)
        item.view = view; app.menu.addItem(item)
        return view
    }
    let first = row("First"), second = row("Second")
    let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!
    let entered = NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
    app.menuOpen = true
    app.menu(app.menu, willHighlight: first.item)
    try check(first.highlighted && !second.highlighted, "Native keyboard selection did not reach custom renderer")
    second.mouseEntered(with: entered)
    second.item?.action = #selector(MenuBoundaryTarget.second(_:))
    try check(second.highlighted && !first.highlighted, "Pointer entry left two highlighted rows")
    try check(app.handleMenuActivation(key) && target.presses == 10, "Activation used previous keyboard row instead of visible pointer row")
    second.item?.isEnabled = false
    try check(app.handleMenuActivation(key) && target.presses == 10, "Disabled selection fell through to native activation")
    second.item?.isEnabled = true; second.item?.isHidden = true
    try check(app.handleMenuActivation(key) && target.presses == 10, "Hidden selection activated")
    app.menu(app.menu, willHighlight: first.item)
    try check(app.handleMenuActivation(key) && target.presses == 11, "Returning to native keyboard navigation failed")
    app.menuOpen = false
    try check(!app.handleMenuActivation(key), "Closed menu captured another window's key")
    let command = NSMenuItem(title: "Deferred", action: #selector(MenuBoundaryTarget.first(_:)), keyEquivalent: "")
    command.target = target
    let commandRow = MenuRowView(item: command, kind: .command)
    command.view = commandRow; app.menu.addItem(command)
    try check(commandRow.activate(), "Deferred command was rejected")
    command.action = #selector(MenuBoundaryTarget.second(_:))
    try drainCommands()
    try check(target.presses == 11, "Refreshed action dispatched a stale deferred command")
    try check(commandRow.activate(), "Updated command could not be retried")
    try drainCommands()
    try check(target.presses == 21, "Unchanged deferred command did not dispatch exactly once")
    print("PASS: native keyboard/custom pointer selection, disabled/hidden/closed activation and deferred action identity (hidden dispatch)")
}
