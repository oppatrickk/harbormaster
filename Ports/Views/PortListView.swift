import SwiftUI

struct PortListView: View {
    @ObservedObject var viewModel: PortsViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if viewModel.rows.isEmpty {
                emptyState
            } else {
                portList
            }

            if let error = viewModel.errorMessage {
                Divider()
                errorBanner(error)
            }

            Divider()
            footer
        }
        .frame(width: 400)
    }

    // MARK: - Sections

    private var activeSummary: String {
        switch viewModel.activeCount {
        case 0: return "None active"
        case 1: return "1 of \(viewModel.watchedCount) active"
        case let count: return "\(count) of \(viewModel.watchedCount) active"
        }
    }

    private var header: some View {
        HStack {
            Text("Ports")
                .font(.system(size: 12, weight: .semibold))

            Spacer()

            Text(activeSummary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Shown only when the watch list itself is empty — a list of all-free ports still
    /// renders as rows.
    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "powerplug")
                    .font(.system(size: 20))
                    .foregroundStyle(.tertiary)
                Text("No ports being watched")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button("Add ports…") {
                    openPreferences()
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
            }
            Spacer()
        }
        .padding(.vertical, 22)
    }

    private var portList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(viewModel.rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider().padding(.leading, 12) }

                    PortRowView(
                        row: row,
                        isConfirmingKill: viewModel.pendingKill == row.id,
                        onCommitLabel: { viewModel.setLabel($0, for: row) },
                        onRequestKill: { viewModel.requestKill(row) },
                        onConfirmKill: { viewModel.confirmKill(row) },
                        onCancelKill: { viewModel.cancelKill() }
                    )
                }
            }
        }
        // Cap the height so a long watch list doesn't produce a popover taller than the screen.
        .frame(maxHeight: 360)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.refreshNow()
            } label: {
                Label("Refresh", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("r")

            Button {
                openPreferences()
            } label: {
                Label("Preferences", systemImage: "gearshape")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(",")

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .keyboardShortcut("q")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func openPreferences() {
        openWindow(id: PortsApp.preferencesWindowID)
        // LSUIElement apps aren't active, so the new window opens behind everything.
        NSApp.activate(ignoringOtherApps: true)
    }
}
