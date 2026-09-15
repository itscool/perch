import SwiftUI

/// Desk identity in two fixed lines: name with the attention badge, then the
/// counts. Nothing here grows with runtime state; facts live in `DeskStatusRows`.
struct DeskHeader: View {
    @ObservedObject var model: DeskModel
    @ObservedObject var page: DeskPageState

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bird.fill").font(.system(size: 26)).foregroundStyle(.teal).padding(.top, 4)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 10) {
                    DeskInlineName(title: "Desk name", saved: model.group.name) { value in
                        model.edit { $0.name = value }
                        if let problem = model.problem { throw KVMError(problem) }
                    }.id(model.group.id).font(.system(size: 27, weight: .semibold)).lineLimit(1).layoutPriority(1)
                    DeskAttentionBadge(model: model, showing: $page.showingAttention)
                }
                Text(Self.counts(computers: model.group.computers.count, screens: model.group.monitors.count)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
        }
    }
    static func counts(computers: Int, screens: Int) -> String {
        "\(computers) computer\(computers == 1 ? "" : "s") · \(screens) screen\(screens == 1 ? "" : "s")"
    }
}

/// Facts about the running desk, each sized to its content: what has control,
/// what could not be confirmed (with its one undo), and a pending conflict
/// (with its one review action). Healthy pages reserve no space here.
struct DeskStatusRows: View {
    @ObservedObject var model: DeskModel
    @ObservedObject var page: DeskPageState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let status = model.status {
                SettingsFeedback(text: status, kind: .information).accessibilityLabel("Keyboard and mouse: " + status)
            }
            if let caution = model.caution {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Label { Text(caution).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "info.circle").accessibilityHidden(true) }
                        .font(.callout).foregroundStyle(.secondary)
                    if model.activeUnconfirmed {
                        Button("Picture didn’t move") { model.backend.revertSwitch() }.buttonStyle(.link).font(.callout).fixedSize()
                            .help("Tell Perch the monitor stayed where it was. Its desktop reconnects and Perch reads the inputs again; nothing is switched.")
                    }
                }
            }
            if model.conflict != nil {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    SettingsFeedback(text: "Two computers changed this desk while apart. Both versions are kept until you choose.", kind: .warning)
                    Button("Review conflicting changes") { page.open(.conflict) }.fixedSize()
                }
            }
        }
    }
}

/// Actionable failures only. Unconfirmed switches are facts in the status rows.
struct DeskAttentionBadge: View {
    @ObservedObject var model: DeskModel
    @Binding var showing: Bool

    private var detail: String? {
        if let problem = model.problem { return problem }
        if !model.monitorProblems.isEmpty {
            let names = model.group.monitors.filter { model.monitorProblems.contains($0.id) }.map(\.name).joined(separator: ", ")
            return "Could not switch " + names + "."
        }
        return nil
    }

    var body: some View {
        if let detail {
            Button { showing.toggle() } label: {
                Label("Needs attention", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(nsColor: StatusColors.warning))
                    .lineLimit(1)
            }
            .buttonStyle(DeskCanvasButtonStyle(padding: 0))
            .help(detail)
            .accessibilityLabel("Desk needs attention. " + detail)
            .popover(isPresented: $showing) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Desk needs attention", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline).foregroundStyle(Color(nsColor: StatusColors.warning))
                    Text(detail).font(.callout).fixedSize(horizontal: false, vertical: true)
                    if !model.monitorProblems.isEmpty {
                        // One named action: the only thing the user can do that Perch cannot.
                        Button("Retry the switch") { model.backend.retryActive(); showing = false }
                            .help("Send the preset’s monitor commands again.")
                    }
                }
                .frame(width: 310, alignment: .leading)
                .padding(14)
            }
        }
    }
}
