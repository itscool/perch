import AppKit
import SwiftUI

/// The bring-over popup's window. It never becomes key or takes focus: the
/// person goes on typing in their app while the copy comes, and pastes there
/// when it is here. Non-activating, never key or main, and its Cancel button
/// takes the first click without the panel becoming key.
final class DeskPastePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Built here and nowhere else, so the construction the tests pin is the
    /// one the app shows.
    static func make() -> DeskPastePanel {
        let panel = DeskPastePanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 120),
                                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.title = "Perch bring over"
        panel.level = .floating; panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        return panel
    }
}

/// A hosting view whose controls take the first click, since the panel is
/// never key.
private final class DeskPasteHost: NSHostingView<DeskPasteOverlay> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// What the overlay draws, copied from `DeskPasteProgress` whenever it changes.
final class DeskPasteViewModel: ObservableObject {
    @Published var title = ""
    @Published var fraction = 0.0
    @Published var line: String?
    @Published var failed = false
    @Published var canCancel = false
    var cancel: () -> Void = {}
    func update(from progress: DeskPasteProgress) {
        title = progress.title; fraction = progress.fraction; line = progress.line
        failed = progress.phase == .failed; canCancel = progress.canCancel
    }
}

/// The popup's look: the lid countdown's material, indigo accent and header,
/// smaller. System colours and materials, so it follows Light and Dark.
struct DeskPasteOverlay: View {
    @ObservedObject var model: DeskPasteViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "bird.fill").foregroundStyle(.indigo)
                Text("Perch").fontWeight(.semibold)
                Spacer()
                if model.canCancel { Button("Cancel") { model.cancel() }.buttonStyle(.bordered).controlSize(.small) }
            }
            Text(model.title).font(.callout)
            if let line = model.line {
                Text(line).font(.caption).foregroundStyle(model.failed ? Color.orange : Color.secondary)
            } else {
                ProgressView(value: model.fraction).tint(.indigo)
            }
        }
        .padding(16).frame(width: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.indigo.opacity(0.22), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.title)
    }
}

/// Puts `DeskPasteProgress` on screen, near the top of the screen the pointer
/// is on, without activating Perch.
final class DeskPastePresenter: DeskPastePresenting {
    private var panel: DeskPastePanel?
    private let model = DeskPasteViewModel()
    func present(_ progress: DeskPasteProgress) {
        guard !SettingsWindow.shared.testing else { return }
        model.update(from: progress)
        model.cancel = { [weak progress] in progress?.cancel() }
        progress.changed = { [weak self, weak progress] in if let self, let progress { self.model.update(from: progress) } }
        progress.closed = { [weak self] in self?.panel?.orderOut(nil) }
        let panel = self.panel ?? {
            let made = DeskPastePanel.make()
            made.contentView = DeskPasteHost(rootView: DeskPasteOverlay(model: model))
            self.panel = made
            return made
        }()
        panel.setContentSize(panel.contentView?.fittingSize ?? NSSize(width: 300, height: 110))
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            let area = screen.visibleFrame
            panel.setFrameTopLeftPoint(NSPoint(x: area.midX - panel.frame.width / 2, y: area.maxY - 24))
        }
        // Never makeKey: ordering front without activating keeps focus where
        // the person is typing.
        panel.orderFrontRegardless()
    }
}
