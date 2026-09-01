import Combine
import Foundation

@MainActor
final class PortsViewModel: ObservableObject {
    /// One row per watched port, active or not.
    @Published private(set) var rows: [PortRow] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastScanDate: Date?

    /// The row currently awaiting kill confirmation, if any.
    @Published var pendingKill: PortRow.ID?

    let preferences: Preferences

    private let labelStore: LabelStore
    private let runner: CommandRunner
    private var refreshTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    private var hasStarted = false

    /// Project name per PID, so the cwd lookup doesn't re-run every refresh tick. An empty
    /// string records "looked up, nothing usable" so those PIDs aren't retried either.
    /// Pruned to live PIDs on each scan so it can't grow without bound.
    private var projectNames: [pid_t: String] = [:]

    init(
        preferences: Preferences = .shared,
        labelStore: LabelStore = LabelStore(),
        runner: CommandRunner = SystemCommandRunner()
    ) {
        self.preferences = preferences
        self.labelStore = labelStore
        self.runner = runner
    }

    deinit {
        refreshTask?.cancel()
    }

    // MARK: - Lifecycle

    /// Idempotent — the menu bar label calls this on appear, which can happen more than once.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        // Restart the loop when the watch list or interval changes. objectWillChange fires
        // *before* the new value lands, so debounce past the edit before re-reading.
        preferences.objectWillChange
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.restartLoop() }
            .store(in: &cancellables)

        restartLoop()
    }

    private func restartLoop() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()

                let interval = self.preferences.effectiveRefreshInterval
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    // MARK: - Scanning

    func refresh() async {
        let watched = preferences.watchedPorts
        let runner = self.runner
        let store = self.labelStore
        let knownNames = projectNames

        // lsof is a blocking spawn — keep it off the main actor so the menu stays responsive.
        let outcome = await Task.detached(priority: .utility) {
            () -> Result<(rows: [PortRow], names: [pid_t: String]), Error> in
            do {
                let listeners = try PortScanner.scan(ports: watched, runner: runner)
                let labels = store.load()

                // Resolve working directories only for PIDs we haven't seen before, then
                // keep just the live ones so the cache stays bounded.
                let livePIDs = listeners.map(\.pid)
                let unknown = livePIDs.filter { knownNames[$0] == nil }

                var names = knownNames
                if !unknown.isEmpty {
                    let resolved = (try? ProcessDirectory.projectNames(
                        for: unknown, runner: runner
                    )) ?? [:]
                    for pid in unknown {
                        names[pid] = resolved[pid] ?? ""   // "" = looked up, nothing usable
                    }
                }
                names = names.filter { livePIDs.contains($0.key) }

                let autoLabels = names.compactMapValues { $0.isEmpty ? nil : $0 }
                return .success((
                    PortRow.rows(
                        watching: watched,
                        listeners: listeners,
                        labels: labels,
                        autoLabels: autoLabels
                    ),
                    names
                ))
            } catch {
                return .failure(error)
            }
        }.value

        guard !Task.isCancelled else { return }

        switch outcome {
        case let .success(result):
            let scanned = result.rows
            projectNames = result.names
            rows = scanned
            errorMessage = nil
            lastScanDate = Date()

            // Drop a stale confirmation if that port went away or freed itself.
            if let pending = pendingKill,
               !scanned.contains(where: { $0.id == pending && $0.isActive }) {
                pendingKill = nil
            }
        case let .failure(error):
            errorMessage = error.localizedDescription
        }
    }

    func refreshNow() {
        Task { await refresh() }
    }

    // MARK: - Watch list

    func addPort(_ port: Int) -> Bool {
        let added = preferences.addPort(port)
        if added { refreshNow() }
        return added
    }

    func removePort(_ port: Int) {
        preferences.removePort(port)
        if pendingKill == port { pendingKill = nil }
        refreshNow()
    }

    // MARK: - Labels

    func setLabel(_ label: String, for row: PortRow) {
        let cleaned = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned != row.label else { return }

        do {
            try labelStore.setLabel(cleaned, for: row.port)
            if let index = rows.firstIndex(where: { $0.id == row.id }) {
                rows[index].label = cleaned
            }
            errorMessage = nil
        } catch {
            errorMessage = "Could not save label: \(error.localizedDescription)"
        }
    }

    // MARK: - Killing

    func requestKill(_ row: PortRow) {
        guard row.isActive else { return }
        pendingKill = row.id
    }

    func cancelKill() {
        pendingKill = nil
    }

    func confirmKill(_ row: PortRow) {
        pendingKill = nil
        guard let pid = row.pid else { return }

        do {
            try ProcessKiller.kill(pid: pid)
            // Per the ports.sh compatibility contract, a killed port's label line is removed.
            try? labelStore.removeLabel(for: row.port)
            if let index = rows.firstIndex(where: { $0.id == row.id }) {
                rows[index] = PortRow(port: row.port, listener: nil, label: "")
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        refreshNow()
    }

    // MARK: - Derived state

    /// What the dropdown lists. Idle ports are still scanned and still hold their labels,
    /// they're just not shown — the list is about what's currently running.
    var visibleRows: [PortRow] { rows.filter(\.isActive) }

    /// Drives the menu bar badge: how many watched ports are actually in use.
    var activeCount: Int { visibleRows.count }

    var watchedCount: Int { rows.count }
}
