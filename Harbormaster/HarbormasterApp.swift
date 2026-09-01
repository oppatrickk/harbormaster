import SwiftUI

@main
struct HarbormasterApp: App {
    static let preferencesWindowID = "preferences"

    @StateObject private var viewModel = PortsViewModel()

    var body: some Scene {
        MenuBarExtra {
            PortListView(viewModel: viewModel)
        } label: {
            MenuBarLabel(count: viewModel.activeCount)
                // The label is the one view that's always instantiated, so it's where the
                // refresh loop gets kicked off — the popover content only exists while open.
                .task { viewModel.start() }
        }
        // .menu can't host editable text fields, and the rows need inline label editing.
        .menuBarExtraStyle(.window)

        Window("Ports Preferences", id: Self.preferencesWindowID) {
            PreferencesView(preferences: viewModel.preferences)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
