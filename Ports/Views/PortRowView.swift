import SwiftUI

struct PortRowView: View {
    let row: PortRow
    let isConfirmingKill: Bool
    let onCommitLabel: (String) -> Void
    let onRequestKill: () -> Void
    let onConfirmKill: () -> Void
    let onCancelKill: () -> Void

    @State private var draftLabel: String
    @FocusState private var isLabelFocused: Bool

    init(
        row: PortRow,
        isConfirmingKill: Bool,
        onCommitLabel: @escaping (String) -> Void,
        onRequestKill: @escaping () -> Void,
        onConfirmKill: @escaping () -> Void,
        onCancelKill: @escaping () -> Void
    ) {
        self.row = row
        self.isConfirmingKill = isConfirmingKill
        self.onCommitLabel = onCommitLabel
        self.onRequestKill = onRequestKill
        self.onConfirmKill = onConfirmKill
        self.onCancelKill = onCancelKill
        _draftLabel = State(initialValue: row.label)
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: row.portText)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(row.isActive ? .primary : .secondary)
                .frame(width: 44, alignment: .leading)

            processColumn
                .frame(width: 110, alignment: .leading)

            TextField("Label", text: $draftLabel)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .focused($isLabelFocused)
                .onSubmit(commitLabel)
                .onChange(of: isLabelFocused) { focused in
                    // Commit on blur as well as on Enter.
                    if !focused { commitLabel() }
                }

            killControl
                .frame(width: 74, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .onChange(of: row.label) { newValue in
            // Pick up out-of-band edits (ports.sh writing the TSV) without stomping typing.
            if !isLabelFocused { draftLabel = newValue }
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
        } else {
            Text("free")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var killControl: some View {
        if !row.isActive {
            // Nothing to kill on a free port; the space stays reserved so rows stay aligned.
            Color.clear.frame(height: 1)
        } else if isConfirmingKill {
            HStack(spacing: 4) {
                Button("Kill", action: onConfirmKill)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)
                    .help(row.pidText.map { "Send SIGKILL to \($0)" } ?? "Send SIGKILL")

                Button(action: onCancelKill) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Cancel")
            }
        } else {
            Button("Kill", action: onRequestKill)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Kill \(row.processName ?? "process") on port " + row.portText)
        }
    }

    private func commitLabel() {
        let cleaned = draftLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        draftLabel = cleaned
        onCommitLabel(cleaned)
    }
}
