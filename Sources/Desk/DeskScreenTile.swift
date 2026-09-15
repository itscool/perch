import SwiftUI
import AppKit

/// One physical screen in the arrangement: name and actions in one row that
/// can never overlap, the editing preset's input choice, and the socket row on
/// the bottom edge. The tile owns selection and drag; the canvas owns the drag
/// state so the snap preview can draw across every tile.
struct DeskScreenTile: View {
    @ObservedObject var model: DeskModel
    let monitor: KVMMonitor
    let index: Int
    let layout: DeskCanvasLayout
    let translation: CGSize
    let wire: DeskWireController
    let controlFrames: [String: CGRect]
    @Binding var renaming: UUID?
    let actions: DeskCanvasActions
    let dragStart: () -> Void
    let dragChange: (CGSize) -> Void
    let dragEnd: (CGSize) -> Void
    @State private var hovered = false

    private var geometry: KVMGeometry { monitor.geometry }
    private var width: CGFloat { max(1, geometry.displayedWidth * layout.scale) }
    private var height: CGFloat { max(1, geometry.displayedHeight * layout.scale) }
    private var compact: Bool { width < 150 || height < 130 }
    private var identifying: Bool { model.backend.isIdentifying(monitor: monitor.id) }
    private var selected: Bool { model.selected == monitor.id }
    private var ports: [KVMConnection] { model.group.connections.filter { $0.monitor == monitor.id } }
    private var horizontalPorts: Bool { ports.isEmpty || (width - 64) / CGFloat(ports.count) >= 68 }
    private var portLabelHeight: CGFloat { max(18, min(72, height - 96)) }
    private var controlIDs: [String] {
        ["rename:", "identify:", "rotate:", "remove:", "more:", "route:", "addPort:"].map { $0 + monitor.id.uuidString } + ports.map { "port:" + $0.id.uuidString }
    }
    private func isControl(_ point: CGPoint) -> Bool { controlIDs.contains { controlFrames[$0]?.contains(point) == true } }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 9)
                .fill(selected ? Color.teal.opacity(0.14) : (hovered ? Color.teal.opacity(0.06) : Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? Color.teal : (hovered ? Color.teal.opacity(0.7) : Color.gray.opacity(0.65)), lineWidth: selected ? 2.5 : (hovered ? 2 : 1.5)))
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 5) {
                titleRow
                if !compact && !identifying {
                    routeRow
                    if height >= 190 { otherPresetRows }
                }
                Spacer(minLength: 0)
                socketRow
            }
            .padding(.horizontal, 7).padding(.top, 6)
        }
        .frame(width: width, height: height)
        .clipped()
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .help("Drag to arrange this physical screen. Perch snaps screens edge to edge so pointer crossing stays continuous. Hold Shift to bypass snapping.")
        .contextMenu { menuItems }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Screen \(index + 1), \(monitor.name), \(model.owner(monitor.id)), \(geometry.rotation.rawValue) degrees")
        .accessibilityAction(named: "Select screen") { model.selected = monitor.id }
        .simultaneousGesture(SpatialTapGesture(coordinateSpace: .named(DeskCanvas.space)).onEnded { value in
            if !isControl(value.location) { model.selected = monitor.id }
        })
        .simultaneousGesture(DragGesture(minimumDistance: 5, coordinateSpace: .named(DeskCanvas.space))
            .onChanged { value in
                if translation == .zero, !isDragging {
                    guard wire.gesture.source == nil, !isControl(value.startLocation) else { return }
                    isDragging = true; dragStart()
                }
                guard isDragging else { return }
                dragChange(value.translation)
            }.onEnded { value in
                guard isDragging else { return }
                isDragging = false
                dragEnd(value.translation)
            })
        .deskControl("region:screen:" + monitor.id.uuidString)
        .offset(x: layout.origin.x + (geometry.x - layout.bounds.minX) * layout.scale + translation.width,
                y: layout.origin.y + (geometry.y - layout.bounds.minY) * layout.scale + translation.height)
    }
    @State private var isDragging = false

    private var titleRow: some View {
        HStack(spacing: 3) {
            if identifying {
                Text("\(index + 1)").font(.system(size: 36, weight: .semibold)).lineLimit(1).allowsHitTesting(false)
            } else if compact {
                Text("\(index + 1)").font(.system(size: 13, weight: .semibold)).allowsHitTesting(false)
                    .help(monitor.name)
            } else {
                Text(monitor.name).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.tail).allowsHitTesting(false)
                Button { renaming = monitor.id } label: { Image(systemName: "pencil").font(.system(size: 11)) }
                    .buttonStyle(DeskCanvasButtonStyle()).accessibilityLabel("Rename " + monitor.name)
                    .help("Rename this screen. Changes save immediately.")
                    .deskControl("rename:" + monitor.id.uuidString)
                    .popover(isPresented: Binding(get: { renaming == monitor.id }, set: { if !$0 { renaming = nil } })) {
                        DeskTextSetting("Screen name", saved: monitor.name) { value in
                            model.edit { group in if let i = group.monitors.firstIndex(where: { $0.id == monitor.id }) { group.monitors[i].name = value } }
                            if let problem = model.problem { throw KVMError(problem) }
                        }.padding(12).frame(width: 250)
                    }
            }
            Spacer(minLength: 4)
            if !identifying { controls }
        }
    }

    /// Frequent actions inline while the tile is wide enough; everything else
    /// (and everything, on a narrow tile) behind one menu that matches the
    /// context menu exactly.
    @ViewBuilder private var controls: some View {
        HStack(spacing: 2) {
            if width >= 300 && !compact {
                Button { actions.identify(monitor.id) } label: { Image(systemName: identifying ? "stop.circle" : "eye") }
                    .accessibilityLabel(identifying ? "Stop identifying \(monitor.name)" : "Identify \(monitor.name)")
                    .help(identifying ? "Stop identifying this screen on every Perch in the desk." : "Show a number on this screen on every Perch in the desk.")
                    .deskControl("identify:" + monitor.id.uuidString)
                Button { model.rotateScreen(monitor.id) } label: { Image(systemName: "rotate.right") }
                    .accessibilityLabel("Rotate \(monitor.name)").help("Rotate clockwise")
                    .deskControl("rotate:" + monitor.id.uuidString)
                Button { actions.remove(monitor.id) } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Remove \(monitor.name)").help("Remove screen")
                    .deskControl("remove:" + monitor.id.uuidString)
            }
            Menu { menuItems } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("More actions for \(monitor.name)")
                .help("Physical size, hardware, ports and more.")
                .deskControl("more:" + monitor.id.uuidString)
        }.font(.system(size: 11, weight: .semibold)).buttonStyle(DeskCanvasButtonStyle())
    }

    @ViewBuilder private var menuItems: some View {
        if width < 300 || compact {
            Button(identifying ? "Stop identifying" : "Identify screen") { actions.identify(monitor.id) }
            Button("Rotate clockwise") { model.rotateScreen(monitor.id) }
        }
        Button("Physical size…") { actions.dimensions(monitor.id) }
        Button("Hardware and control…") { actions.hardware(monitor.id) }
        Button("Add port…") { actions.addPort(monitor.id) }
        Divider()
        Button("Remove screen…", role: .destructive) { actions.remove(monitor.id) }
    }

    /// The editing preset's choice for this screen, as a visible control.
    private var routeRow: some View {
        HStack(spacing: 5) {
            Text("Preset \(model.presetIndex + 1)").font(.system(size: 10, weight: .medium)).foregroundStyle(.teal).fixedSize()
            Picker("Input for preset \(model.presetIndex + 1) on \(monitor.name)", selection: Binding<UUID?>(
                get: { model.preset.assignments.first { $0.monitor == monitor.id }?.connection },
                set: { model.assign($0, monitor: monitor.id) })) {
                Text("Unchanged").tag(UUID?.none)
                ForEach(ports) { port in
                    Text(port.inputName + " · " + (model.group.computers.first { $0.id == port.computer }?.name ?? "no computer")).tag(Optional(port.id))
                }
            }
            .pickerStyle(.menu).labelsHidden().controlSize(.small)
            .frame(maxWidth: max(60, width - 84), alignment: .leading)
            .help("Which input this screen switches to when preset \(model.presetIndex + 1) plays. Unchanged leaves the screen as it is.")
            .deskControl("route:" + monitor.id.uuidString)
        }
    }

    /// What the other two presets do with this screen, as plain text, so the
    /// tile body says something useful instead of staying blank.
    private var otherPresetRows: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(model.group.presets.enumerated()), id: \.element.id) { index, preset in
                if index != model.presetIndex {
                    let port = preset.assignments.first { $0.monitor == monitor.id }.flatMap { a in model.group.connections.first { $0.id == a.connection } }
                    let owner = port.flatMap { p in model.group.computers.first { $0.id == p.computer }?.name }
                    Text("Preset \(index + 1) · " + (port.map { $0.inputName + " · " + (owner ?? "no computer") } ?? "unchanged"))
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                }
            }
        }.padding(.leading, 2).allowsHitTesting(false)
    }

    private var socketRow: some View {
        HStack(alignment: .bottom, spacing: horizontalPorts ? 6 : 8) {
            ForEach(ports) { port in
                DeskPortSocket(model: model, port: port, horizontal: horizontalPorts, labelHeight: portLabelHeight, wire: wire, cable: actions.cable, editPort: actions.editPort)
            }
            Button { actions.addPort(monitor.id) } label: { Text("+ Port").font(.system(size: 10, weight: .medium)) }
                .buttonStyle(DeskCanvasButtonStyle()).help("Add a monitor port")
                .deskControl("addPort:" + monitor.id.uuidString).padding(.bottom, 3)
        }
        // The socket row is pinned to the physical screen edge so cables meet it.
        .frame(maxWidth: .infinity, alignment: .bottomLeading)
    }
}

/// Dashed preview of where a dragged screen will land, with alignment guides.
struct DeskSnapPreview: View {
    let drag: DeskScreenDrag
    let others: [CGRect]
    let bypass: Bool
    var body: some View {
        let layout = drag.layout
        let proposed = DeskCanvasGeometry.rectangle(drag.geometry).offsetBy(dx: drag.translation.width / layout.scale, dy: drag.translation.height / layout.scale)
        let preview = DeskScreenPlacement.preview(proposed, among: others, scale: layout.scale, bypass: bypass)
        ZStack(alignment: .topLeading) {
            if !bypass && !preview.guides.isEmpty {
                Path { path in
                    let r = preview.rectangle, p = layout.point(x: r.minX, y: r.minY)
                    path.addRoundedRect(in: CGRect(origin: p, size: CGSize(width: r.width * layout.scale, height: r.height * layout.scale)), cornerSize: CGSize(width: 9, height: 9))
                }.stroke(Color.teal, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                ForEach(Array(preview.guides.enumerated()), id: \.offset) { _, guide in
                    let a = guide.horizontal ? layout.point(x: guide.start, y: guide.position) : layout.point(x: guide.position, y: guide.start)
                    let b = guide.horizontal ? layout.point(x: guide.end, y: guide.position) : layout.point(x: guide.position, y: guide.end)
                    Path { path in path.move(to: a); path.addLine(to: b) }.stroke(Color.pink, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    Text(guide.label).font(.system(size: 9, weight: .medium)).padding(2)
                        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 3))
                        .offset(x: a.x + 3, y: a.y - 14)
                }
            }
        }.allowsHitTesting(false)
    }
}
