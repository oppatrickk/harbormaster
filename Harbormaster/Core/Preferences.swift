import Combine
import Foundation

/// UserDefaults-backed settings. Launch-at-login is deliberately *not* stored here —
/// `LoginItem` reads its state from SMAppService so the two can't drift.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    enum Default {
        /// Ports watched on first launch, listed individually.
        static let watchedPorts = Array(3000...3010)
        static let refreshInterval: Double = 3
    }

    private enum Key {
        static let watchedPorts = "watchedPorts"
        static let refreshInterval = "refreshInterval"
        // Pre-individual-ports keys, read once to migrate then left alone.
        static let legacyRangeStart = "portRangeStart"
        static let legacyRangeEnd = "portRangeEnd"
    }

    static let portBounds = 1...65535
    static let intervalBounds = 1.0...60.0

    private let defaults: UserDefaults

    /// Always sorted, deduplicated, and in-bounds — enforced by `normalize`.
    @Published private(set) var watchedPorts: [Int] {
        didSet { defaults.set(watchedPorts, forKey: Key.watchedPorts) }
    }

    @Published var refreshInterval: Double {
        didSet { defaults.set(refreshInterval, forKey: Key.refreshInterval) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // An explicitly stored list always wins, even when empty — "watch nothing" is a
        // legitimate choice and must not silently spring back to the defaults.
        if let stored = Self.decodeStoredPorts(defaults.object(forKey: Key.watchedPorts)) {
            watchedPorts = Self.normalize(stored)
        } else if let start = defaults.object(forKey: Key.legacyRangeStart) as? Int,
                  let end = defaults.object(forKey: Key.legacyRangeEnd) as? Int {
            // Migrate an older contiguous range into the individual ports it covered, so
            // upgrading doesn't silently change which ports are watched.
            watchedPorts = Self.normalize(Array(min(start, end)...max(start, end)))
        } else {
            watchedPorts = Self.normalize(Default.watchedPorts)
        }

        refreshInterval = defaults.object(forKey: Key.refreshInterval) as? Double
            ?? Default.refreshInterval
    }

    // MARK: - Watched ports

    /// Adds a port. Returns false if it's out of bounds or already watched.
    @discardableResult
    func addPort(_ port: Int) -> Bool {
        guard Self.portBounds.contains(port), !watchedPorts.contains(port) else { return false }
        watchedPorts = Self.normalize(watchedPorts + [port])
        return true
    }

    func removePort(_ port: Int) {
        guard watchedPorts.contains(port) else { return }
        watchedPorts = watchedPorts.filter { $0 != port }
    }

    var effectiveRefreshInterval: Double {
        refreshInterval.clamped(to: Self.intervalBounds)
    }

    func resetToDefaults() {
        watchedPorts = Self.normalize(Default.watchedPorts)
        refreshInterval = Default.refreshInterval
    }

    private static func normalize(_ ports: [Int]) -> [Int] {
        Array(Set(ports.filter { portBounds.contains($0) })).sorted()
    }

    /// Coerces a stored value into port numbers, tolerating the several shapes a plist can
    /// legitimately hold.
    ///
    /// `defaults write … -array 3000 3001` stores *strings*, not integers, so a plain
    /// `as? [Int]` cast fails and would silently discard a hand-edited watch list. Unparseable
    /// entries are dropped individually rather than throwing the whole list away.
    ///
    /// Returns nil only when the key is absent or isn't an array at all — that's the signal
    /// to fall through to migration or defaults.
    private static func decodeStoredPorts(_ raw: Any?) -> [Int]? {
        guard let elements = raw as? [Any] else { return nil }

        return elements.compactMap { element in
            if let number = element as? NSNumber { return number.intValue }
            if let text = element as? String {
                return Int(text.trimmingCharacters(in: .whitespaces))
            }
            return nil
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
