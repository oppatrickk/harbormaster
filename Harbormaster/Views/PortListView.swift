import SwiftUI

/// Propagates the measured height of the row stack up to the ScrollView.
private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension ClosedRange where Bound == CGFloat {
    /// `ClosedRange.clamped(to:)` clamps a range to a range; this clamps a value.
    func clamped(_ value: Bound) -> Bound {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}

struct PortListView: View {
    @ObservedObject var viewModel: PortsViewModel
    @Environment(\.openWindow) private var openWindow

    /// Measured height of the row stack, used to size the ScrollView explicitly.
    @State private var contentHeight: CGFloat = 0

    /// Widest process column any row asked for. Rows all render at this width so they stay
    /// aligned, but the column no longer reserves room for a long name when every process
    /// on the list is called "node".
    @State private var processColumnWidth: CGFloat = 0

    /// Which row's label field is being edited, or nil for none.
    ///
    /// Owned here rather than inside the row so that a click anywhere else in the popover —
    /// or Escape, or Enter — can put it back to nil. A `MenuBarExtra` window won't drop first
    /// responder on its own, so without an explicit way out the cursor stays in the field.
    @FocusState private var focusedRow: PortRow.ID?

    private let maxListHeight: CGFloat = 360

    /// Floor keeps a lone short name ("go") from collapsing the column into the label field;
    /// ceiling keeps one `language_server_macos_arm` from eating the space this whole change
    /// is meant to give back.
    private let processColumnRange: ClosedRange<CGFloat> = 62...150

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if viewModel.visibleRows.isEmpty {
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
        // Wide enough that a typical project name fits the label field without truncating;
        // anything longer is still readable via the row's hover tooltips.
        .frame(width: 480)
        // Clicking any dead space — header, padding, between rows — ends the edit. Buttons and
        // text fields are hit first, so this only catches clicks nothing else wanted.
        .contentShape(Rectangle())
        .onTapGesture { focusedRow = nil }
    }

    // MARK: - Sections

    private var activeSummary: String {
        switch viewModel.activeCount {
        case 0: return "None active"
        case 1: return "1 active"
        case let count: return "\(count) active"
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

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "powerplug")
                    .font(.system(size: 20))
                    .foregroundStyle(.tertiary)

                // "Nothing running" and "nothing configured" need different fixes, so they
                // shouldn't read the same.
                if viewModel.watchedCount == 0 {
                    Text("No ports being watched")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Button("Add ports…") { openPreferences() }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                } else {
                    Text(verbatim: "Nothing listening on your \(viewModel.watchedCount) "
                         + "watched port\(viewModel.watchedCount == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 22)
    }

    private var portList: some View {
        ScrollView {
            // A plain VStack, not LazyVStack: the lazy variant only materializes rows that
            // are already visible, so it reports zero height to the measurement below and
            // the list can never size itself out of being empty.
            VStack(spacing: 0) {
                ForEach(Array(viewModel.visibleRows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider().padding(.leading, 12) }

                    PortRowView(
                        row: row,
                        processColumnWidth: processColumnRange.clamped(processColumnWidth),
                        focusedRow: $focusedRow,
                        onCommitLabel: { viewModel.setLabel($0, for: row) },
                        onKill: { viewModel.kill(row) }
                    )
                }
            }
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                }
            )
        }
        .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
        .onPreferenceChange(ProcessColumnWidthKey.self) { processColumnWidth = $0 }
        // An explicit height is required, not just a cap. A MenuBarExtra window proposes an
        // unspecified height to its content, and a ScrollView given no definite height
        // collapses to zero — which renders the whole list invisible. Measure the rows and
        // size to them, capped so a long watch list can't outgrow the screen.
        .frame(height: min(max(contentHeight, 1), maxListHeight))
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
        openWindow(id: HarbormasterApp.preferencesWindowID)
        // LSUIElement apps aren't active, so the new window opens behind everything.
        NSApp.activate(ignoringOtherApps: true)
    }
}
