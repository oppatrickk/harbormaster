import SwiftUI

struct PortRowView: View {
    let port: ListeningPort
    let isConfirmingKill: Bool
    let onCommitLabel: (String) -> Void
    let onRequestKill: () -> Void
    let onConfirmKill: () -> Void
    let onCancelKill: () -> Void

    @State private var draftLabel: String
    @FocusState private var isLabelFocused: Bool

    init(
        port: ListeningPort,
        isConfirmingKill: Bool,
        onCommitLabel: @escaping (String) -> Void,
        onRequestKill: @escaping () -> Void,
        onConfirmKill: @escaping () -> Void,
        onCancelKill: @escaping () -> Void
    ) {
        self.port = port
        self.isConfirmingKill = isConfirmingKill
        self.onCommitLabel = onCommitLabel
        self.onRequestKill = onRequestKill
        self.onConfirmKill = onConfirmKill
        self.onCancelKill = onCancelKill
        _draftLabel = State(initialValue: port.label)
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("\(port.port)")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .frame(width: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(port.processName)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text("PID \(port.pid)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .onChange(of: port.label) { newValue in
            // Pick up out-of-band edits (ports.sh writing the TSV) without stomping typing.
            if !isLabelFocused { draftLabel = newValue }
        }
    }

    @ViewBuilder
    private var killControl: some View {
        if isConfirmingKill {
            HStack(spacing: 4) {
                Button("Kill", action: onConfirmKill)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)
                    .help("Send SIGKILL to PID \(port.pid)")

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
                .help("Kill \(port.processName) on port \(port.port)")
        }
    }

    private func commitLabel() {
        let cleaned = draftLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        draftLabel = cleaned
        onCommitLabel(cleaned)
    }
}
