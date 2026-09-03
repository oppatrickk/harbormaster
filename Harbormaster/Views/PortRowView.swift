import SwiftUI

private extension View {
    /// `.help("")` still installs a tooltip rect, which pops an empty box on hover. Attach
    /// the tooltip only when there is something to say.
    @ViewBuilder
    func helpIfPresent(_ text: String) -> some View {
        if text.isEmpty { self } else { help(text) }
    }
}

/// Carries each row's natural process-column width up to the list, which takes the maximum
/// and hands one shared width back down. Rows stay aligned without a fixed column that's
/// mostly padding when every process is called "node".
struct ProcessColumnWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Neutral chip at rest, filled with `hoverFill` under the cursor, darker while pressed.
///
/// Both row actions use this. A plain `.bordered` button with a tint only recolors the title,
/// which is far too quiet for Kill — a control that SIGKILLs a process on a single click.
private struct RowActionButtonStyle: ButtonStyle {
    let isHovering: Bool
    let hoverFill: Color
    var horizontalPadding: CGFloat = 10

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(isHovering ? Color.white : Color.primary)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(fill(pressed: configuration.isPressed))
            )
            .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private func fill(pressed: Bool) -> Color {
        if pressed { return hoverFill.opacity(0.75) }
        if isHovering { return hoverFill }
        return Color.secondary.opacity(0.18)
    }
}

struct PortRowView: View {
    let row: PortRow
    /// Shared across every row, measured by the list. See `ProcessColumnWidthKey`.
    let processColumnWidth: CGFloat
    let onCommitLabel: (String) -> Void
    let onKill: () -> Void

    /// Which row's label field holds focus, owned by the list.
    ///
    /// This deliberately isn't a private `@FocusState` on the row: nothing outside the text
    /// field could then clear it, so once you clicked in there was no way back out.
    @FocusState.Binding var focusedRow: PortRow.ID?

    @Environment(\.openURL) private var openURL

    @State private var draftLabel: String
    @State private var isHoveringKill = false
    @State private var isHoveringOpen = false

    init(
        row: PortRow,
        processColumnWidth: CGFloat,
        focusedRow: FocusState<PortRow.ID?>.Binding,
        onCommitLabel: @escaping (String) -> Void,
        onKill: @escaping () -> Void
    ) {
        self.row = row
        self.processColumnWidth = processColumnWidth
        _focusedRow = focusedRow
        self.onCommitLabel = onCommitLabel
        self.onKill = onKill
        _draftLabel = State(initialValue: row.label)
    }

    private var isLabelFocused: Bool { focusedRow == row.id }

    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: row.portText)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(row.isActive ? .primary : .secondary)
                .frame(width: 44, alignment: .leading)

            processColumn
                .frame(width: processColumnWidth, alignment: .leading)
                .background(processWidthProbe)

            // Passing a String (not a literal) selects the StringProtocol overload, so the
            // detected project name renders verbatim rather than as a LocalizedStringKey.
            TextField(row.labelPlaceholder, text: $draftLabel)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .focused($focusedRow, equals: row.id)
                // Enter commits *and* gives up focus. Committing alone left the cursor
                // parked in the field with no obvious way out.
                .onSubmit {
                    commitLabel()
                    focusedRow = nil
                }
                // Escape abandons the edit, the standard macOS text-field behaviour.
                .onExitCommand {
                    draftLabel = row.label
                    focusedRow = nil
                }
                .onChange(of: isLabelFocused) { focused in
                    // Commit on blur as well as on Enter.
                    if !focused { commitLabel() }
                }
                // A label longer than the field is clipped with no ellipsis to hint at it,
                // so hovering is the only way to read the rest.
                .helpIfPresent(labelTooltip)

            HStack(spacing: 6) {
                openControl
                killControl
            }
            .frame(width: 82, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .onChange(of: row.label) { newValue in
            // Pick up out-of-band edits (ports.sh writing the TSV) without stomping typing.
            if !isLabelFocused { draftLabel = newValue }
        }
    }

    /// A hidden, unconstrained copy of the process column that reports the width this row
    /// *would* like. It sits in a `.background`, so it never influences the row's own layout,
    /// and `.fixedSize()` makes it ignore the proposed width — otherwise it would just
    /// measure the column we already forced it into.
    @ViewBuilder
    private var processWidthProbe: some View {
        if let processName = row.processName, let pidText = row.pidText {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: processName).font(.system(size: 12))
                Text(verbatim: pidText).font(.system(size: 10))
            }
            .fixedSize()
            .hidden()
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ProcessColumnWidthKey.self,
                        value: proxy.size.width
                    )
                }
            )
        }
    }

    @ViewBuilder
    private var processColumn: some View {
        if let processName = row.processName, let pidText = row.pidText {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: processName)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(verbatim: pidText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            // Long process names are middle-truncated; hovering shows the whole thing.
            .help(processName + " — " + pidText)
        } else {
            Text("free")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    /// Opens `http://localhost:<port>` in the default browser.
    ///
    /// Shown for every active row. Plenty of dev ports don't speak HTTP — a Postgres on 5432
    /// will just produce a browser error — but the app can't tell what protocol is behind a
    /// listening socket, and guessing from the port number would be wrong as often as right.
    @ViewBuilder
    private var openControl: some View {
        if row.isActive, let url = row.localURL {
            Button {
                openURL(url)
            } label: {
                // The diagonal arrow is the conventional "opens externally" mark. A globe or
                // a browser glyph would name a destination; this names the action.
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(
                RowActionButtonStyle(
                    isHovering: isHoveringOpen,
                    hoverFill: .accentColor,
                    horizontalPadding: 7
                )
            )
            .onHover { isHoveringOpen = $0 }
            .help("Open " + url.absoluteString)
            .accessibilityLabel("Open port " + row.portText + " in browser")
        } else {
            Color.clear.frame(height: 1)
        }
    }

    @ViewBuilder
    private var killControl: some View {
        if !row.isActive {
            // Nothing to kill on a free port; the space stays reserved so rows stay aligned.
            Color.clear.frame(height: 1)
        } else {
            Button("Kill", action: onKill)
                .buttonStyle(RowActionButtonStyle(isHovering: isHoveringKill, hoverFill: .red))
                .onHover { isHoveringKill = $0 }
                // No confirm step, so the tooltip is the only warning that the click is final.
                .help(killTooltip)
        }
    }

    private var killTooltip: String {
        let target = row.pidText.map { "\(row.processName ?? "process") (\($0))" }
            ?? row.processName
            ?? "process"
        return "SIGKILL \(target) on port \(row.portText) — no confirmation"
    }

    /// What hovering the label field reveals: the typed label, or the auto-detected project
    /// name when the field is still empty. Empty when there is neither, so no blank tooltip
    /// pops up on a bare row.
    private var labelTooltip: String {
        let typed = draftLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        guard let autoLabel = row.autoLabel else { return "" }
        return autoLabel + " (auto-detected)"
    }

    private func commitLabel() {
        let cleaned = draftLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        draftLabel = cleaned
        onCommitLabel(cleaned)
    }
}
