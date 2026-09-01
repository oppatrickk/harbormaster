import ServiceManagement
import SwiftUI

struct PreferencesView: View {
    @ObservedObject var preferences: Preferences

    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginItemError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            portRangeSection
            Divider()
            refreshSection
            Divider()
            launchAtLoginSection

            Divider()

            HStack {
                Button("Restore Defaults") { preferences.resetToDefaults() }
                Spacer()
                Text("Labels: ~/.ports_labels.tsv")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { launchAtLogin = LoginItem.isEnabled }
    }

    // MARK: - Sections

    private var portRangeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Port Range").font(.headline)

            HStack(spacing: 8) {
                TextField(
                    "From",
                    value: $preferences.portRangeStart,
                    formatter: Self.portFormatter
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)

                Text("to").foregroundStyle(.secondary)

                TextField(
                    "To",
                    value: $preferences.portRangeEnd,
                    formatter: Self.portFormatter
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)

                Spacer()
            }

            Text("Watching \(rangeDescription) — \(portCount) ports.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var refreshSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Refresh").font(.headline)

            HStack(spacing: 10) {
                Slider(
                    value: $preferences.refreshInterval,
                    in: Preferences.intervalBounds,
                    step: 1
                )
                Text("\(Int(preferences.effectiveRefreshInterval))s")
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 40, alignment: .trailing)
            }

            Text("How often the port list is rescanned.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var launchAtLoginSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Launch at login", isOn: launchAtLoginBinding)
                .font(.headline)

            if let loginItemError {
                Text(loginItemError)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Status: \(LoginItem.statusDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    /// Writes straight through to SMAppService and reads the result back, so the toggle can
    /// never show a state the system doesn't actually have.
    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { desired in
                do {
                    try LoginItem.setEnabled(desired)
                    loginItemError = nil
                } catch {
                    loginItemError = "Could not \(desired ? "enable" : "disable") "
                        + "launch at login: \(error.localizedDescription) "
                        + "Try moving Ports.app to /Applications and relaunching it."
                }
                launchAtLogin = LoginItem.isEnabled
            }
        )
    }

    private var rangeDescription: String {
        let range = preferences.portRange
        return range.lowerBound == range.upperBound
            ? "\(range.lowerBound)"
            : "\(range.lowerBound)–\(range.upperBound)"
    }

    private var portCount: Int {
        preferences.portRange.count
    }

    private static let portFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.allowsFloats = false
        formatter.minimum = NSNumber(value: Preferences.portBounds.lowerBound)
        formatter.maximum = NSNumber(value: Preferences.portBounds.upperBound)
        formatter.usesGroupingSeparator = false
        return formatter
    }()
}
