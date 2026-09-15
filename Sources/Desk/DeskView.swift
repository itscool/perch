import SwiftUI

/// The Desk page: identity, facts, the three preset cards, and one desk
/// surface. Everything temporary is a sheet routed through `DeskPageState`.
struct DeskView: View {
    @ObservedObject var model: DeskModel
    @StateObject private var page = DeskPageState()

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                DeskHeader(model: model, page: page)
                DeskStatusRows(model: model, page: page)
            }.padding(.horizontal, 24).padding(.top, 6).padding(.bottom, 14)
            DeskPresetStrip(model: model).padding(.horizontal, 24).padding(.bottom, 16)
            DeskCanvas(model: model, actions: canvasActions)
                .frame(minHeight: 260, maxHeight: .infinity)
                .padding(.horizontal, 24).padding(.bottom, 24)
        }
        .frame(minWidth: 560, minHeight: 440)
        .onChange(of: page.sheet) { _, next in if next != nil { model.problem = nil } }
        .sheet(isPresented: Binding(get: { page.sheet != nil }, set: { if !$0 { page.close() } })) { DeskSheetRouter(model: model, page: page) }
    }

    private var canvasActions: DeskCanvasActions {
        DeskCanvasActions(
            remove: { id in model.selected = id; page.open(.removeScreen(id)) },
            dimensions: { id in model.selected = id; page.open(.dimensions(id)) },
            identify: { id in model.selected = id; model.identify() },
            hardware: { id in model.selected = id; page.open(.monitorSetup) },
            cable: { port, computer in page.beginCable(port, computer, model: model) },
            editPort: { id in page.open(.port(id)) },
            addPort: { id in model.selected = id; page.draftScreen = id; page.open(.connections(screen: id)) },
            computerDetails: { id in page.computerDetails(id, model: model) },
            removeComputer: { id in page.draftComputer = id; page.open(.removeComputer(id)) },
            addComputer: { page.open(.addComputer) },
            addScreen: { page.addScreen(model: model) })
    }
}
