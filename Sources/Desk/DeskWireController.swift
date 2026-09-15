import SwiftUI
import AppKit

/// Anchors of every socket, keyed by socket id, resolved in the desk document.
struct DeskCableAnchors: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}

/// Frames of interactive controls and node regions in the desk coordinate
/// space. Only actual controls exclude a screen drag; node regions only
/// exclude an empty-surface pan.
struct DeskControlFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}
extension View {
    func deskControl(_ id: String) -> some View {
        background(GeometryReader { area in
            Color.clear.preference(key: DeskControlFrames.self, value: [id: area.frame(in: .named(DeskCanvas.space))])
        })
    }
}

/// Local canvas interaction only; no event posting or hardware access.
@MainActor final class DeskWireController: ObservableObject {
    private final class WeakSocket { weak var view: DeskWireSocketView?; init(_ view: DeskWireSocketView) { self.view = view } }
    private var sockets: [String: WeakSocket] = [:]
    private var escapeMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var geometryObservers: [NSObjectProtocol] = []
    private var geometryPending = false
    private var lastGeometry: [String: CGRect] = [:]
    func scheduleGeometryUpdate() {
        guard gesture.source != nil, !geometryPending else { return }
        geometryPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }; self.geometryPending = false; self.geometryDidChange()
        }
    }
    func geometryDidChange() {
        guard gesture.source != nil else { return }
        let current = sockets.compactMapValues { $0.view.map { $0.convert($0.bounds.intersection($0.visibleRect), to: nil) } }
        guard current != lastGeometry else { return }
        lastGeometry = current
        move(to: gesture.point)
    }
    private(set) var gesture = DeskWireGesture()
    private(set) var target: String?
    var connect: ((UUID, UUID) -> Void)?
    var presetConnect: ((Int, UUID, UUID) -> Void)?
    var connection: ((String) -> KVMConnection?)?
    var rewire: ((KVMConnection, KVMConnection) -> Void)?
    private var pickedUp: KVMConnection?
    var detachedPort: UUID? { gesture.dragging ? pickedUp?.id : nil }
    var cableSource: String? {
        if gesture.dragging, let computer = pickedUp?.computer { return "computer:" + computer.uuidString }
        return gesture.source
    }
    func register(_ view: DeskWireSocketView) {
        sockets[view.socketID] = WeakSocket(view)
        if gesture.source != nil { observeGeometry(of: view); scheduleGeometryUpdate() }
    }
    private func observeGeometry(of view: NSView) {
        var ancestor: NSView? = view
        while let current = ancestor {
            current.postsFrameChangedNotifications = true; current.postsBoundsChangedNotifications = true
            ancestor = current.superview
        }
    }
    func remove(_ view: DeskWireSocketView) {
        guard sockets[view.socketID]?.view === view else { return }
        sockets[view.socketID] = nil
        if gesture.source == view.socketID || cableSource == view.socketID { cancel() } else { scheduleGeometryUpdate() }
    }
    func socket(_ id: String?) -> DeskWireSocketView? { id.flatMap { sockets[$0]?.view } }
    func center(_ id: String?) -> CGPoint? {
        guard let view = socket(id), view.window != nil else { return nil }
        return view.convert(view.attachmentPoint, to: nil)
    }
    func begin(_ id: String, at point: CGPoint) {
        cancel(); gesture.begin(id, at: point)
        if let cable = connection?(id), cable.computer != nil { pickedUp = cable }
        for socket in sockets.values { if let view = socket.view { observeGeometry(of: view) } }
        for name in [NSView.frameDidChangeNotification, NSView.boundsDidChangeNotification] {
            geometryObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleGeometryUpdate() }
            })
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { self.cancel(); return nil }; return event
        }
        if let window = socket(id)?.window {
            resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancel() }
            }
        }
    }
    func move(to point: CGPoint) {
        guard let source = gesture.source, let origin = socket(source) else { return }
        if let pickedUp, connection?(source) != pickedUp { cancel(); return }
        gesture.move(to: point)
        guard let effectiveSource = cableSource else { return }
        target = gesture.dragging ? sockets.keys.sorted().first { key in
            guard DeskWireGesture.compatible(effectiveSource, key), let view = socket(key), view.window === origin.window, !view.isHiddenOrHasHiddenAncestor else { return false }
            let visible = view.bounds.intersection(view.visibleRect)
            return !visible.isEmpty && visible.insetBy(dx: -6, dy: -6).contains(view.convert(point, from: nil))
        } : nil
        refresh()
    }
    /// Return true only for a click; callers may then show their menu on mouse-up.
    func end(_ id: String, at point: CGPoint) -> Bool {
        guard gesture.source == id else { return false }
        move(to: point)
        // A geometry refresh may cancel a cable changed by another peer.
        guard gesture.source == id else { return false }
        let destination = target
        if gesture.dragging, let pickedUp {
            let targetCable = destination.flatMap { connection?($0) }
            cancel()
            if let targetCable, targetCable.id != pickedUp.id { rewire?(pickedUp, targetCable) }
            return false
        }
        let inside = socket(id).map { $0.bounds.contains($0.convert(point, from: nil)) } ?? false
        let result = gesture.finish(insideSource: inside, target: destination)
        cancel()
        if case let .connect(source, target) = result {
            let port = source.hasPrefix("port:") ? source : target
            if let p = UUID(uuidString: String(port.dropFirst(5))) {
                let computer = source.hasPrefix("computer:") ? source : target
                if computer.hasPrefix("computer:"), let c = UUID(uuidString: String(computer.dropFirst(9))) { connect?(p, c) }
                let preset = source.hasPrefix("preset:") ? source : target
                if preset.hasPrefix("preset:") {
                    let parts = preset.split(separator: ":")
                    if parts.count == 3, let c = UUID(uuidString: String(parts[1])), let slot = Int(parts[2]) { presetConnect?(slot, c, p) }
                }
            }
        }
        return result == .click
    }
    func cancel() {
        gesture = DeskWireGesture(); target = nil; pickedUp = nil
        for observer in geometryObservers { NotificationCenter.default.removeObserver(observer) }
        geometryObservers = []; lastGeometry = [:]
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }; escapeMonitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }; resignObserver = nil
        refresh()
    }
    private func refresh() { objectWillChange.send(); for socket in sockets.values { socket.view?.needsDisplay = true } }
}

final class DeskSocketMenu: NSMenu {
    private final class Action: NSObject { let run: () -> Void; init(_ run: @escaping () -> Void) { self.run = run }; @objc func invoke() { run() } }
    private var actions: [Action] = []
    @discardableResult
    func action(_ title: String, enabled: Bool = true, checked: Bool = false, help: String? = nil, _ run: @escaping () -> Void) -> NSMenuItem {
        let target = Action(run); actions.append(target)
        let item = NSMenuItem(title: title, action: #selector(Action.invoke), keyEquivalent: "")
        autoenablesItems = false
        item.target = target; item.isEnabled = enabled; item.toolTip = help; item.state = checked ? .on : .off; addItem(item)
        return item
    }
}

struct DeskWireSocket: NSViewRepresentable {
    let id: String
    let connected: Bool
    let label: String
    let controller: DeskWireController
    var presetNumbers: [Int] = []
    var highlighted = false
    var activeRouting = false
    /// Computer connectors draw their own slot number; port sockets show
    /// membership as SwiftUI chips beside the label instead.
    var drawsNumbers = true
    var menu: (() -> DeskSocketMenu)? = nil
    func makeNSView(context: Context) -> DeskWireSocketView { DeskWireSocketView(frame: .zero) }
    func updateNSView(_ view: DeskWireSocketView, context: Context) {
        if view.socketID != id { view.controller?.remove(view) }
        view.socketID = id; view.connected = connected; view.presetNumbers = presetNumbers; view.highlighted = highlighted; view.activeRouting = activeRouting; view.controller = controller; view.makeMenu = menu
        view.drawsNumbers = drawsNumbers
        view.setAccessibilityLabel(label)
        let routeState = (highlighted ? "; selected in editing preset" : "") + (activeRouting ? "; active now" : "")
        view.setAccessibilityValue(presetNumbers.isEmpty ? (activeRouting ? "Active now" : "No presets") : "Presets " + presetNumbers.map(String.init).joined(separator: ", ") + routeState)
        view.toolTip = label + (id.hasPrefix("preset:") ? ". Drag to a monitor input to assign this preset; click for choices." : (connected && id.hasPrefix("port:") ? ". Drag to move this cable to another input; Esc cancels. Click for the port menu." : ". Drag to another connector to draw a wire. Click for connections."))
        controller.register(view); view.needsDisplay = true
    }
    static func dismantleNSView(_ view: DeskWireSocketView, coordinator: ()) { view.controller?.remove(view) }
}
final class DeskWireSocketView: NSView {
    var socketID = ""
    var connected = false
    var presetNumbers: [Int] = []
    var highlighted = false
    var activeRouting = false
    var drawsNumbers = true
    weak var controller: DeskWireController?
    var makeMenu: (() -> DeskSocketMenu)?
    private(set) var hovered = false
    var attachmentPoint: CGPoint {
        let isComputer = socketID.hasPrefix("computer:") || socketID.hasPrefix("preset:")
        return CGPoint(x: bounds.midX, y: isComputer ? bounds.maxY : bounds.minY)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override init(frame: NSRect) {
        super.init(frame: frame); setAccessibilityElement(true); setAccessibilityRole(.button)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { controller?.begin(socketID, at: event.locationInWindow) }
    override func mouseDragged(with event: NSEvent) { controller?.move(to: event.locationInWindow) }
    override func mouseUp(with event: NSEvent) { if controller?.end(socketID, at: event.locationInWindow) == true { showMenu() } }
    override func rightMouseDown(with event: NSEvent) { mouseDown(with: event) }
    override func rightMouseDragged(with event: NSEvent) { mouseDragged(with: event) }
    override func rightMouseUp(with event: NSEvent) { mouseUp(with: event) }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { controller?.cancel() }
        else if event.keyCode == 36 || event.keyCode == 49 { showMenu() }
        else { super.keyDown(with: event) }
    }
    override func accessibilityPerformPress() -> Bool { showMenu(); return makeMenu != nil }
    private func showMenu() {
        guard let menu = makeMenu?() else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.minY), in: self)
    }
    override func draw(_ dirtyRect: NSRect) {
        let center = attachmentPoint
        let isComputer = socketID.hasPrefix("computer:") || socketID.hasPrefix("preset:")
        let active = controller?.target == socketID
        func halfCircle(_ radius: CGFloat) -> NSBezierPath {
            let path = NSBezierPath()
            path.appendArc(withCenter: center, radius: radius, startAngle: isComputer ? 180 : 0, endAngle: isComputer ? 360 : 180)
            path.close(); return path
        }
        if hovered || active {
            NSColor.systemTeal.withAlphaComponent(active ? 0.25 : 0.14).setFill(); halfCircle(12).fill()
        }
        // The straight edge meets the device outline; the curved side is inside.
        let socket = halfCircle(8)
        NSColor.controlBackgroundColor.setFill(); socket.fill()
        let detached = controller?.detachedPort.map { socketID == "port:" + $0.uuidString } ?? false
        let base = isComputer ? NSColor.systemBlue : NSColor.systemIndigo
        let color = hovered || active ? NSColor.systemTeal : base
        color.setFill(); color.setStroke()
        socket.lineWidth = active || hovered ? 2.5 : 1.5
        if connected && !detached { socket.fill() } else { socket.stroke() }
        if highlighted {
            let ring = halfCircle(10.5); ring.lineWidth = 2; NSColor.systemTeal.setStroke(); ring.stroke()
        }
        if activeRouting {
            let ring = halfCircle(12); ring.lineWidth = 2; StatusColors.success.setStroke(); ring.stroke()
        }
        if drawsNumbers, !presetNumbers.isEmpty {
            let text = presetNumbers.map(String.init).joined(separator: " ") as NSString
            let numberColor = highlighted ? NSColor.systemTeal : (activeRouting ? StatusColors.success : base)
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: numberColor]
            let size = text.size(withAttributes: attrs)
            // Membership stays visible for every preset, outside the half circle.
            text.draw(at: CGPoint(x: center.x - size.width / 2, y: isComputer ? center.y - 9 - size.height : center.y + 9), withAttributes: attrs)
        }
        if active { let ring = halfCircle(11); ring.lineWidth = 2; ring.stroke() }
    }
}
struct DeskWireOverlay: NSViewRepresentable {
    @ObservedObject var controller: DeskWireController
    func makeNSView(context: Context) -> DeskWireOverlayView { DeskWireOverlayView(frame: .zero) }
    func updateNSView(_ view: DeskWireOverlayView, context: Context) { view.controller = controller; view.needsDisplay = true }
}
final class DeskWireOverlayView: NSView {
    weak var controller: DeskWireController?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func layout() {
        super.layout(); needsDisplay = true; controller?.scheduleGeometryUpdate()
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let controller, controller.gesture.dragging, let start = controller.center(controller.cableSource) else { return }
        let a = convert(start, from: nil), b = convert(controller.center(controller.target) ?? controller.gesture.point, from: nil)
        let path = NSBezierPath(); path.move(to: a)
        let middle = (a.y + b.y) / 2
        path.curve(to: b, controlPoint1: CGPoint(x: a.x, y: middle), controlPoint2: CGPoint(x: b.x, y: middle))
        path.lineWidth = 2.5
        (controller.target == nil ? NSColor.secondaryLabelColor : NSColor.systemTeal).setStroke()
        if controller.target == nil { path.setLineDash([4, 4], count: 2, phase: 0) }
        path.stroke()
    }
}
