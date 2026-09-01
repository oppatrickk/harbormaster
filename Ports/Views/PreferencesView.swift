import ServiceManagement
import SwiftUI

struct PreferencesView: View {
    @ObservedObject var preferences: Preferences

    @State private var newPortText = ""
    @State private var addError: String?
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginItemError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            watchedPortsSection
            Divider()
            refreshSection
            Divider()
            launchAtLoginSection

            Divider()

            HStack {
                Button("Restore Defaults") {
                    preferences.resetToDefaults()
                    addError = nil
                }
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

    // MARK: - Watched ports

    private var watchedPortsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Watched Ports").font(.headline)
                Spacer()
                Text("\(preferences.watchedPorts.count) watched")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            portList

            HStack(spacing: 8) {
                TextField("Add port", text: $newPortText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .onSubmit(addPort)

                Button("Add", action: addPort)
                    .disabled(newPortText.trimmingCharacters(in: .whitespaces).isEmpty)

                Spacer()
            }

            if let addError {
                Text(addError)
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Text("Each port is watched individually — they don't have to be consecutive.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var portList: some View {
        if preferences.watchedPorts.isEmpty {
            HStack {
                Spacer()
                Text("No ports watched yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.quaternary, lineWidth: 1)
            )
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(preferences.watchedPorts, id: \.self) { port in
                        HStack {
                            Text("\(port)")
                                .font(.system(size: 12, design: .monospaced))
                            Spacer()
                            Button {
                                preferences.removePort(port)
                                addError = nil
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Stop watching port \(port)")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)

                        if port != preferences.watchedPorts.last {
                            Divider()
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(height: 140)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.quaternary, lineWidth: 1)
            )
        }
    }

    private func addPort() {
        let trimmed = newPortText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        guard let port = Int(trimmed) else {
            addError = "“\(trimmed)” isn't a number."
            return
        }
        guard Preferences.portBounds.contains(port) else {
            addError = "Port must be between \(Preferences.portBounds.lowerBound) "
                + "and \(Preferences.portBounds.upperBound)."
            return
        }
        guard !preferences.watchedPorts.contains(port) else {
            addError = "Port \(port) is already watched."
            return
        }

        preferences.addPort(port)
        newPortText = ""
        addError = nil
    }

    // MARK: - Refresh

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

            Text("How often the watched ports are rescanned.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Launch at login

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
}
