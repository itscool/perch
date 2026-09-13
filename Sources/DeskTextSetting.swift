import SwiftUI

struct DeskTextSetting: View {
    let title: String
    let saved: String
    var numeric = false
    let save: (String) throws -> Void
    @State private var draft: DeskTextDraft
    @State private var problem: String?
    @FocusState private var focused: Bool
    init(_ title: String, saved: String, numeric: Bool = false, save: @escaping (String) throws -> Void) {
        self.title = title; self.saved = saved; self.numeric = numeric; self.save = save
        _draft = State(initialValue: DeskTextDraft(saved))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            TextField(title, text: Binding(get: { draft.text }, set: { value in
                draft.text = value; problem = nil
                if !numeric && !draft.conflict { commit() }
            })).textFieldStyle(.roundedBorder).accessibilityLabel(title).focused($focused)
                .onSubmit { commit() }
                .onChange(of: focused) { _, active in if !active && problem == nil { commit() } }
            if draft.conflict {
                Text("Changed on another computer. Saved: \(draft.baseline). Your unfinished edit is kept until you choose.").font(.caption).foregroundStyle(.orange)
                HStack {
                    Button("Use saved") { draft.accept(saved); problem = nil }
                    Button("Keep my edit") { draft.conflict = false; commit() }
                }.controlSize(.small)
            }
            if let problem {
                Text(problem).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                Button("Retry saving") { commit() }.controlSize(.small).disabled(draft.conflict)
            } else if numeric && draft.dirty && !draft.conflict {
                Text("Not saved yet. Press Return or leave this field to save a complete input code (1–65535). Saved: \(saved.isEmpty ? "not set" : saved). Invalid edits are discarded when leaving this editor.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if draft.dirty && (problem != nil || draft.conflict) {
                Text("Leaving this editor discards an unfinished edit.").font(.caption).foregroundStyle(.secondary)
            }
        }.onChange(of: saved) { _, value in draft.receive(value); if !draft.dirty { problem = nil } }
            .onDisappear { if problem == nil { commit() } }
    }
    private func commit() {
        guard draft.dirty, !draft.conflict else { return }
        do {
            if numeric { guard let code = UInt16(draft.text), code > 0 else { throw KVMError("Enter a complete input code from 1 to 65535. The saved code is unchanged.") } }
            try save(draft.text); draft.accept(draft.text); problem = nil
        } catch { problem = "Not saved. " + error.localizedDescription }
    }
}

/// Rename belongs to the object. Selecting a preset and activating it remain
/// separate actions; opening an editor never changes its live assignment.
struct DeskInlineName: View {
    let title: String
    let saved: String
    var select: (() -> Void)? = nil
    let save: (String) throws -> Void
    @State private var editing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let select { Button(saved, action: select).buttonStyle(.plain) }
                else { Text(saved) }
                Button { editing.toggle() } label: {
                    Image(systemName: editing ? "chevron.up" : "pencil").font(.system(size: 11))
                }.buttonStyle(.plain).accessibilityLabel(editing ? "Collapse \(title) editor" : "Rename \(title)")
                    .help(editing ? "Collapse the name editor. Valid changes are already saved." : "Rename \(title). Changes save immediately.")
            }
            if editing {
                DeskTextSetting(title, saved: saved, save: save)
                    .font(.body).padding(8)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
            }
        }
    }
}
