import SwiftUI

struct PortListView: View {
    @ObservedObject var viewModel: PortsViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if viewModel.ports.isEmpty {
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
        .frame(width: 380)
    }

    // MARK: - Sections

    private var activeSummary: String {
        switch viewModel.activeCount {
        case 0: return "None active"
        case 1: return "1 port active"
        case let count: return "\(count) ports active"
        }
    }

    private var header: some View {
        HStack {
            Text("Ports \(viewModel.rangeDescription)")
                .font(.system(size: 12, weight: .semibold))

            Spacer()

            Text(activeSummary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 4) {
                Image(systemName: "powerplug")
                    .font(.system(size: 20))
                    .foregroundStyle(.tertiary)
                Text("Nothing listening on \(viewModel.rangeDescription)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 22)
    }

    private var portList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(viewModel.ports.enumerated()), id: \.element.id) { index, port in
                    if index > 0 { Divider().padding(.leading, 12) }

                    PortRowView(
                        port: port,
                        isConfirmingKill: viewModel.pendingKill == port.id,
                        onCommitLabel: { viewModel.setLabel($0, for: port) },
                        onRequestKill: { viewModel.requestKill(port) },
                        onConfirmKill: { viewModel.confirmKill(port) },
                        onCancelKill: { viewModel.cancelKill() }
                    )
                }
            }
        }
        // Cap the height so a wide range doesn't produce a popover taller than the screen.
        .frame(maxHeight: 340)
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
                openWindow(id: PortsApp.preferencesWindowID)
                // LSUIElement apps aren't active, so the new window opens behind everything.
                NSApp.activate(ignoringOtherApps: true)
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
}
