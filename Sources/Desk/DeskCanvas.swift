import SwiftUI
import AppKit

/// Everything the canvas can ask the page to do. Live hosts and the lab supply
/// the same set; missing actions are no-ops.
struct DeskCanvasActions {
    var remove: (UUID) -> Void = { _ in }
    var dimensions: (UUID) -> Void = { _ in }
    var identify: (UUID) -> Void = { _ in }
    var hardware: (UUID) -> Void = { _ in }
    var cable: (UUID, UUID) -> Void = { _, _ in }
    var editPort: (UUID) -> Void = { _ in }
    var addPort: (UUID) -> Void = { _ in }
    var computerDetails: (UUID) -> Void = { _ in }
    var removeComputer: (UUID) -> Void = { _ in }
    var addComputer: () -> Void = {}
    var addScreen: () -> Void = {}
}

extension DeskCanvasGeometry {
    /// The rendered rectangle of a screen's saved geometry, in millimetres.
    static func rectangle(_ g: KVMGeometry) -> CGRect { CGRect(x: g.x, y: g.y, width: g.displayedWidth, height: g.displayedHeight) }
    init(monitors: [KVMMonitor], viewport: CGSize, computersHeight: CGFloat) {
        self.init(rectangles: monitors.map { Self.rectangle($0.geometry) }, viewport: viewport, computersHeight: computersHeight)
    }
}

struct DeskScreenDrag {
    let id: UUID
    let geometry: KVMGeometry
    let layout: DeskCanvasLayout
    var translation: CGSize
}

private struct DeskRowHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// The desk surface: a fixed toolbar, then one finite pannable document that
/// holds the screen graph, the cables and the computer row. The document is
/// exactly the viewport while the arrangement fits, and grows only when the
/// tiles would otherwise shrink below their readable minimum.
struct DeskCanvas: View {
    static let space = "deskScreenCanvas"
    @ObservedObject var model: DeskModel
    let actions: DeskCanvasActions
    @State private var renaming: UUID?
    @State private var drag: DeskScreenDrag?
    @State private var controlFrames: [String: CGRect] = [:]
    @StateObject private var wire = DeskWireController()
    @State private var snapBypassed = false
    @State private var modifierMonitor: Any?
    @State private var pan = CGSize.zero
    @State private var computersHeight: CGFloat = 96

    init(model: DeskModel, actions: DeskCanvasActions) { self.model = model; self.actions = actions }
    /// Positional form used by the offscreen renderer and the lab.
    init(model: DeskModel, remove: @escaping (UUID) -> Void, dimensions: @escaping (UUID) -> Void, identify: @escaping (UUID) -> Void,
         hardware: @escaping (UUID) -> Void, cable: @escaping (UUID, UUID) -> Void, editPort: @escaping (UUID) -> Void, addPort: @escaping (UUID) -> Void,
         computerDetails: @escaping (UUID) -> Void, removeComputer: @escaping (UUID) -> Void, addComputer: @escaping () -> Void, addScreen: @escaping () -> Void = {}) {
        self.init(model: model, actions: .init(remove: remove, dimensions: dimensions, identify: identify, hardware: hardware, cable: cable, editPort: editPort,
                                              addPort: addPort, computerDetails: computerDetails, removeComputer: removeComputer, addComputer: addComputer, addScreen: addScreen))
    }

    var body: some View {
        VStack(spacing: 10) {
            DeskSurfaceToolbar(model: model, addScreen: actions.addScreen, addComputer: actions.addComputer)
            GeometryReader { viewport in
                let geometry = DeskCanvasGeometry(monitors: model.group.monitors, viewport: viewport.size, computersHeight: computersHeight)
                PannableSurface(documentSize: geometry.documentSize, viewportSize: viewport.size, pan: $pan,
                                coordinateSpace: Self.space, scrollerInset: 12, allowsDrag: true,
                                dragHitTest: { point in drag == nil && wire.gesture.source == nil && !controlFrames.values.contains { $0.contains(point) } }) {
                    document(geometry)
                }
            }
        }
    }

    private func document(_ geometry: DeskCanvasGeometry) -> some View {
        let layout = drag?.layout ?? geometry.layout
        let rectangles = model.group.monitors.map { DeskCanvasGeometry.rectangle($0.geometry) }
        return VStack(alignment: .leading, spacing: DeskCanvasGeometry.rowSpacing) {
            ZStack(alignment: .topLeading) {
                if model.group.monitors.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "display.2").font(.system(size: 40, weight: .light))
                        Text("Add a screen, then connect its inputs to the computers below.").foregroundStyle(.secondary)
                    }.frame(width: geometry.graphSize.width, height: geometry.graphSize.height)
                }
                ForEach(Array(model.group.monitors.enumerated()), id: \.element.id) { index, monitor in
                    DeskScreenTile(model: model, monitor: monitor, index: index, layout: layout,
                                   translation: drag?.id == monitor.id ? drag!.translation : .zero,
                                   wire: wire, controlFrames: controlFrames, renaming: $renaming, actions: actions,
                                   dragStart: { beginDrag(monitor, layout: layout) },
                                   dragChange: { translation in if drag?.id == monitor.id { drag?.translation = translation } },
                                   dragEnd: { translation in endDrag(monitor, translation: translation) })
                }
                if let drag {
                    DeskSnapPreview(drag: drag, others: model.group.monitors.filter { $0.id != drag.id }.map { DeskCanvasGeometry.rectangle($0.geometry) }, bypass: snapBypassed)
                }
            }
            .frame(width: geometry.graphSize.width, height: geometry.graphSize.height, alignment: .topLeading)
            computersRow.frame(width: geometry.graphSize.width, alignment: .leading)
        }
        .padding(DeskCanvasGeometry.padding)
        .frame(width: geometry.documentSize.width, height: geometry.documentSize.height, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(nsColor: .underPageBackgroundColor).opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onChange(of: model.group.monitors.map(\.id)) { _, ids in if let current = drag, !ids.contains(current.id) { finishDrag() } }
        .onPreferenceChange(DeskControlFrames.self) { controlFrames = $0 }
        .onChange(of: model.group.connections) { _, _ in wire.move(to: wire.gesture.point) }
        .onAppear {
            wire.connection = { id in model.group.connections.first { "port:" + $0.id.uuidString == id } }
            // A wire from a computer claims the input for that computer, then
            // matches its display: automatically when unambiguous, else the cable step.
            wire.draw = { slot, computer, port in
                model.drawWire(slot: slot, computer: computer, port: port)
                if model.problem == nil { actions.cable(port, computer) }
            }
            wire.editingSlot = { model.presetIndex + 1 }
            wire.routed = { connection in model.preset.assignments.contains { $0.connection == connection } }
            wire.moveWire = { from, to in model.moveWire(from: from, to: to) }
            wire.removeWire = { port in model.removeWire(port) }
        }
        .onDisappear { finishDrag(); wire.cancel() }
        .overlay { DeskWireOverlay(controller: wire).allowsHitTesting(false) }
        .backgroundPreferenceValue(DeskCableAnchors.self) { anchors in DeskWireLayer(model: model, wire: wire, anchors: anchors) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Desk arrangement: \(rectangles.count) screens")
    }

    private var computersRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The connectors poke above the cards; keep the title clear of them.
            Text("Computers").font(.headline).padding(.bottom, 6)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 12)], alignment: .leading, spacing: 10) {
                ForEach(model.group.computers) { computer in
                    DeskComputerCard(model: model, computer: computer, wire: wire, details: actions.computerDetails)
                }
            }
            Text("Teal line: the preset you are editing. Green glow: on the displays now. Both together: this preset is the one showing. Drag between a computer’s numbered connector and a monitor input to connect them. Drag a connected input to another input, or into empty space, to change the preset you are editing. Play switches the displays.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .background(GeometryReader { area in Color.clear.preference(key: DeskRowHeight.self, value: area.size.height) })
        .onPreferenceChange(DeskRowHeight.self) { height in if abs(computersHeight - height) > 0.5 { computersHeight = height } }
    }

    private func beginDrag(_ monitor: KVMMonitor, layout: DeskCanvasLayout) {
        guard drag == nil else { return }
        drag = DeskScreenDrag(id: monitor.id, geometry: monitor.geometry, layout: layout, translation: .zero)
        model.selected = monitor.id
        snapBypassed = NSEvent.modifierFlags.contains(.shift)
        modifierMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in snapBypassed = event.modifierFlags.contains(.shift); return event }
    }
    private func endDrag(_ monitor: KVMMonitor, translation: CGSize) {
        guard let started = drag, started.id == monitor.id else { return }
        defer { finishDrag() }
        guard let current = model.group.monitors.first(where: { $0.id == monitor.id }), current.geometry == started.geometry else {
            model.problem = "This screen changed on another computer while you were moving it. Try the move again."; return
        }
        let proposed = DeskCanvasGeometry.rectangle(started.geometry).offsetBy(dx: translation.width / started.layout.scale, dy: translation.height / started.layout.scale)
        let placed = DeskScreenPlacement.preview(proposed, among: model.group.monitors.filter { $0.id != monitor.id }.map { DeskCanvasGeometry.rectangle($0.geometry) }, scale: started.layout.scale, bypass: NSEvent.modifierFlags.contains(.shift)).rectangle
        model.move(monitor.id, x: placed.minX, y: placed.minY)
    }
    private func finishDrag() {
        drag = nil; snapBypassed = false
        if let modifierMonitor { NSEvent.removeMonitor(modifierMonitor) }; modifierMonitor = nil
    }
}

/// Add actions stay outside the pannable document so they are reachable at
/// every width; the editing preset is named once, here.
struct DeskSurfaceToolbar: View {
    @ObservedObject var model: DeskModel
    let addScreen: () -> Void
    let addComputer: () -> Void
    @State private var confirmingReset = false
    var body: some View {
        HStack(spacing: 12) {
            Text("Editing \(model.preset.name)").font(.headline).foregroundStyle(.teal).lineLimit(1)
                .accessibilityLabel("Editing preset \(model.presetIndex + 1), \(model.preset.name)")
            Spacer(minLength: 8)
            Button(action: addScreen) { Label("Add screen", systemImage: "plus") }
                .disabled(model.group.monitors.count >= 16)
                .help("Add a physical screen to this desk. Up to 16 screens.")
            Button(action: addComputer) { Label("Add computer", systemImage: "plus") }
                .disabled(model.group.computers.count >= 16)
                .help(model.backend.wording.addComputerHelp)
            Button { confirmingReset = true } label: { Label("Reset desk…", systemImage: "arrow.counterclockwise") }
                .disabled(model.group.monitors.isEmpty && model.group.presets.allSatisfy { $0.assignments.isEmpty })
                .help("Start this desk’s screens, inputs and presets over. Your paired Macs stay paired.")
                .confirmationDialog("Reset this desk?", isPresented: $confirmingReset) {
                    Button("Reset desk", role: .destructive) { model.resetLayout() }
                } message: {
                    Text("Every screen, input and connection is removed on all Macs in this desk. Your Macs stay paired and preset names stay. Add your screens again afterwards.")
                }
        }.fixedSize(horizontal: false, vertical: true)
    }
}

/// One curve per preset route: from the computer's numbered connector to the
/// monitor input that preset uses.
struct DeskWireLayer: View {
    @ObservedObject var model: DeskModel
    @ObservedObject var wire: DeskWireController
    let anchors: [String: Anchor<CGRect>]
    var body: some View {
        GeometryReader { area in
            ForEach(model.group.connections) { connection in
                ForEach(Array(model.group.presets.enumerated()), id: \.element.id) { slot, preset in
                    // Only the wire in hand leaves the canvas while it is being
                    // dragged. The same input's wires in other presets are not
                    // being moved, so they stay where they are.
                    if preset.assignments.contains(where: { $0.connection == connection.id }),
                       wire.detachedPort != connection.id || slot != model.presetIndex,
                       let computer = connection.computer,
                       let start = anchors["preset:\(computer.uuidString):\(slot + 1)"], let end = anchors["port:" + connection.id.uuidString] {
                        let source = area[start], target = area[end]
                        let chosen = slot == model.presetIndex
                        let activeRoute = model.active?.id == preset.id
                        let focused = chosen && model.selected == connection.monitor
                        let startPoint = CGPoint(x: source.midX, y: source.minY)
                        let endPoint = CGPoint(x: target.midX, y: target.maxY)
                        let middleY = (startPoint.y + endPoint.y) / 2
                        // Two different things, shown two different ways rather than as
                        // two colours of the same line: the preset being edited is the
                        // drawn line, and what is on the displays now glows behind it.
                        let strokeColor: Color = chosen ? .teal.opacity(focused ? 1 : 0.85) : (activeRoute ? Color(nsColor: StatusColors.success).opacity(0.8) : .secondary.opacity(0.35))
                        let lineWidth: CGFloat = chosen ? (focused ? 3 : 2.5) : 1.5
                        let path = Path { path in
                            path.move(to: startPoint)
                            path.addCurve(to: endPoint, control1: CGPoint(x: startPoint.x, y: middleY), control2: CGPoint(x: endPoint.x, y: middleY))
                        }
                        if activeRoute {
                            path.stroke(Color(nsColor: StatusColors.success).opacity(0.3), style: StrokeStyle(lineWidth: lineWidth + 7, lineCap: .round))
                        }
                        path.stroke(strokeColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    }
                }
            }
        }.allowsHitTesting(false)
    }
}
