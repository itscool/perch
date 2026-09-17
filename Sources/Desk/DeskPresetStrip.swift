import SwiftUI

/// One state per card, chosen by priority. The card shows exactly one of these
/// in its status slot, so nothing can overlap the shortcut or the Play button.
enum DeskPresetStatus: Equatable {
    case switching
    case notMapped(String)
    case needsAttention(String)
    case active(unconfirmed: Bool, edited: Bool)
    case screens(Int)
}

extension DeskModel {
    func presetStatus(_ index: Int) -> DeskPresetStatus {
        let preset = group.presets[index]
        if switchingPreset == preset.id { return .switching }
        if let issue = readinessIssue(for: index) { return preset.assignments.isEmpty ? .notMapped(issue) : .needsAttention(issue) }
        if active?.id == preset.id { return .active(unconfirmed: activeUnconfirmed, edited: changedSinceUse) }
        return .screens(preset.assignments.count)
    }
}

/// The three preset cards in one row that wraps at narrow widths instead of
/// squeezing names to nothing.
struct DeskPresetStrip: View {
    @ObservedObject var model: DeskModel
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210, maximum: 360), spacing: 12)], alignment: .leading, spacing: 12) {
            ForEach(Array(model.group.presets.enumerated()), id: \.element.id) { index, preset in
                DeskPresetCard(model: model, index: index, preset: preset)
            }
        }
    }
}

struct DeskPresetCard: View {
    @ObservedObject var model: DeskModel
    let index: Int
    let preset: KVMPreset
    @State private var hovered = false
    @State private var confirmingClear = false

    private var editing: Bool { model.presetIndex == index }
    private var readiness: String? { model.readinessIssue(for: index) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 7) {
                DeskInlineName(title: "Preset \(index + 1) name", saved: preset.name, select: { select() }) { value in
                    model.edit { group in
                        if let i = group.presets.firstIndex(where: { $0.id == preset.id }) { group.presets[i].name = value }
                    }
                    if let problem = model.problem { throw KVMError(problem) }
                }.id(preset.id).font(.system(size: 14, weight: .semibold))
                DeskPresetStatusView(status: model.presetStatus(index))
            }.frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 5) {
                Button { model.activatePreset(index) } label: { Image(systemName: "play.fill").font(.system(size: 12, weight: .semibold)).frame(width: 26, height: 23) }
                    .buttonStyle(DeskCanvasButtonStyle()).foregroundStyle(.teal)
                    .disabled(readiness != nil || model.switchingPreset != nil)
                    .accessibilityLabel("Switch to \(preset.name)")
                    .help(readiness ?? model.backend.wording.presetActivationHelp)
                Button { confirmingClear = true } label: { Image(systemName: "eraser").font(.system(size: 11, weight: .semibold)).frame(width: 26, height: 20) }
                    .buttonStyle(DeskCanvasButtonStyle()).foregroundStyle(.secondary)
                    .disabled(preset.assignments.isEmpty)
                    .accessibilityLabel("Clear \(preset.name)")
                    .help(preset.assignments.isEmpty ? "This preset has no connections to clear." : "Clear this preset’s connections. Screens, inputs and cables stay.")
                    .confirmationDialog("Clear \(preset.name)?", isPresented: $confirmingClear) {
                        Button("Clear preset", role: .destructive) { model.clearPreset(index) }
                    } message: { Text("It stops switching any screen. Your screens, inputs and cables stay as they are.") }
                Text(preset.shortcut.label).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).fixedSize()
            }
        }
        .padding(12)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(editing ? Color.teal.opacity(hovered ? 0.16 : 0.10) : (hovered ? Color.teal.opacity(0.06) : Color(nsColor: .controlBackgroundColor))))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(editing ? Color.teal : Color(nsColor: .separatorColor), lineWidth: editing ? 2 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { select() }
        .onHover { hovered = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityValue(editing ? "Editing" : "")
        .accessibilityAction(named: "Edit preset") { select() }
        .help(editing ? "This preset’s connections are shown in the screens below." : "Select this card to edit its connections. Play switches to it.")
    }
    private func select() { model.presetIndex = index; model.problem = nil }
}

/// The single status slot of a preset card.
struct DeskPresetStatusView: View {
    let status: DeskPresetStatus
    @State private var showing = false
    var body: some View {
        switch status {
        case .switching:
            Label("Switching…", systemImage: "arrow.triangle.2.circlepath")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                .help("Perch is sending this preset’s monitor commands.")
        case .notMapped(let detail), .needsAttention(let detail):
            let title = { if case .notMapped = status { return "Not mapped" } else { return "Needs attention" } }()
            Button { showing.toggle() } label: {
                Label(title, systemImage: "exclamationmark.triangle.fill").font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: StatusColors.warning)).lineLimit(1).truncationMode(.tail)
            }.buttonStyle(DeskCanvasButtonStyle(padding: 0)).help(detail)
                .accessibilityLabel(title + ". " + detail)
                .popover(isPresented: $showing) { Text(detail).font(.callout).frame(width: 250, alignment: .leading).padding(14) }
        case .active(let unconfirmed, let edited):
            let text = edited ? "Active now · edited" : unconfirmed ? "Active · unconfirmed" : "Active now"
            let color: Color = unconfirmed ? .teal : Color(nsColor: StatusColors.success)
            Text(text)
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(color)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(color.opacity(0.12), in: Capsule()).lineLimit(1)
                .help(edited ? "This preset is still active on the displays, but its saved connections were edited. Play it again to apply those edits."
                      : unconfirmed ? "Perch sent this preset’s monitor commands and they were accepted, but the monitor cannot report its input. The picture usually changed."
                      : "This is the preset currently active on the displays. Selecting another card only changes what you edit.")
        case .screens(let count):
            Text("\(count) screen\(count == 1 ? "" : "s")").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}
