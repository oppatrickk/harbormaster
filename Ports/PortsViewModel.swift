import Combine
import Foundation

@MainActor
final class PortsViewModel: ObservableObject {
    @Published private(set) var ports: [ListeningPort] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastScanDate: Date?

    /// The row currently awaiting kill confirmation, if any.
    @Published var pendingKill: ListeningPort.ID?

    let preferences: Preferences

    private let labelStore: LabelStore
    private let runner: CommandRunner
    private var refreshTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    private var hasStarted = false

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

        // Restart the loop when the range or interval changes. objectWillChange fires
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
        let range = preferences.portRange
        let runner = self.runner
        let store = self.labelStore

        // lsof is a blocking spawn — keep it off the main actor so the menu stays responsive.
        let outcome = await Task.detached(priority: .utility) { () -> Result<[ListeningPort], Error> in
            do {
                let scanned = try PortScanner.scan(range: range, runner: runner)
                let labels = store.load()
                return .success(scanned.map { port in
                    var labeled = port
                    labeled.label = labels[port.port] ?? ""
                    return labeled
                })
            } catch {
                return .failure(error)
            }
        }.value

        guard !Task.isCancelled else { return }

        switch outcome {
        case let .success(scanned):
            ports = scanned
            errorMessage = nil
            lastScanDate = Date()

            // Drop a stale confirmation if that row vanished between refreshes.
            if let pending = pendingKill, !scanned.contains(where: { $0.id == pending }) {
                pendingKill = nil
            }
        case let .failure(error):
            errorMessage = error.localizedDescription
        }
    }

    func refreshNow() {
        Task { await refresh() }
    }

    // MARK: - Labels

    func setLabel(_ label: String, for port: ListeningPort) {
        let cleaned = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned != port.label else { return }

        do {
            try labelStore.setLabel(cleaned, for: port.port)
            if let index = ports.firstIndex(where: { $0.id == port.id }) {
                ports[index].label = cleaned
            }
            errorMessage = nil
        } catch {
            errorMessage = "Could not save label: \(error.localizedDescription)"
        }
    }

    // MARK: - Killing

    func requestKill(_ port: ListeningPort) {
        pendingKill = port.id
    }

    func cancelKill() {
        pendingKill = nil
    }

    func confirmKill(_ port: ListeningPort) {
        pendingKill = nil
        do {
            try ProcessKiller.kill(pid: port.pid)
            // The port is gone, so its label has nothing left to describe.
            try? labelStore.removeLabel(for: port.port)
            ports.removeAll { $0.id == port.id }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        refreshNow()
    }

    // MARK: - Derived state

    var activeCount: Int { ports.count }

    var rangeDescription: String {
        let range = preferences.portRange
        return range.lowerBound == range.upperBound
            ? "\(range.lowerBound)"
            : "\(range.lowerBound)–\(range.upperBound)"
    }
}
