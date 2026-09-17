import SwiftUI

/// Every temporary step the Desk page can open. The backend renders the steps
/// it owns; the shared editors (cable, port, size, remove screen) are the page's.
enum DeskSheet: Equatable {
    case addComputer
    case addScreen
    case connections(screen: UUID)
    case removeConnection(UUID)
    case cable(port: UUID, computer: UUID)
    case port(UUID)
    case removeComputer(UUID)
    case computerDetails(UUID)
    case removeScreen(UUID)
    case conflict
    case dimensions(UUID)
    case control
    case monitorSetup

    /// The object this step edits, or nil for the page's selected screen.
    var subject: UUID? {
        switch self {
        case .computerDetails(let id), .removeComputer(let id), .removeConnection(let id), .removeScreen(let id), .dimensions(let id), .port(let id): id
        case .connections(let screen): screen
        case .cable(let port, _): port
        default: nil
        }
    }
}

/// Transient page state: which sheet is open and the drafts it edits. Nothing
/// here is saved; the desk itself lives in `DeskModel`.
final class DeskPageState: ObservableObject {
    @Published var sheet: DeskSheet?
    @Published var draftName = ""
    @Published var draftInput = "HDMI 1"
    @Published var draftComputer: UUID?
    @Published var draftScreen: UUID?
    @Published var confirmingRemoval = false
    @Published var fallbackAspect = 16.0 / 9.0
    @Published var showingAttention = false

    func open(_ sheet: DeskSheet) { confirmingRemoval = false; self.sheet = sheet }
    func close() { sheet = nil; confirmingRemoval = false }

    /// A cable drawn from a computer to a port. Resolve it without a sheet when
    /// the choice is unambiguous; otherwise open the cable step.
    func beginCable(_ port: UUID, _ computer: UUID, model: DeskModel) {
        guard let connection = model.group.connections.first(where: { $0.id == port }), model.group.computers.contains(where: { $0.id == computer }) else { return }
        model.selected = connection.monitor
        if connection.computer == computer && connection.localDisplay != nil { return }
        model.backend.refreshScreens()
        // An input already claimed for this computer but still waiting for its
        // display resolves exactly like a free one.
        let free = connection.computer == nil || connection.computer == computer
        let options = model.cableOptions(for: computer).filter { model.cableConflict($0, port: port) == nil }
        if options.isEmpty, free {
            if connection.computer == nil { model.backend.mapComputer(port: port, computer: computer) }
            return
        }
        let alreadyWired = options.contains { option in model.group.connections.contains { $0.computer == computer && $0.localDisplay == option.display } }
        if let only = options.first, options.count == 1, free, !alreadyWired {
            model.backend.map(port: port, option: only.id)
            if model.problem == nil { return }
        }
        open(.cable(port: port, computer: computer))
    }
    func addScreen(model: DeskModel) {
        draftName = "New screen"; draftComputer = model.group.computers.first?.id; draftScreen = nil
        open(.addScreen)
    }
    func computerDetails(_ id: UUID, model: DeskModel) {
        draftComputer = id; draftName = model.group.computers.first { $0.id == id }?.name ?? "Computer"
        open(.computerDetails(id))
    }
}
