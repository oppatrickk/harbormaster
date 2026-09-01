import Combine
import Foundation

/// UserDefaults-backed settings. Launch-at-login is deliberately *not* stored here —
/// `LoginItem` reads its state from SMAppService so the two can't drift.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    enum Default {
        static let portRangeStart = 3000
        static let portRangeEnd = 3010
        static let refreshInterval: Double = 3
    }

    private enum Key {
        static let portRangeStart = "portRangeStart"
        static let portRangeEnd = "portRangeEnd"
        static let refreshInterval = "refreshInterval"
    }

    /// Sane bounds so a typo can't spawn an lsof scan over all 65k ports every 3 seconds.
    static let portBounds = 1...65535
    static let intervalBounds = 1.0...60.0

    private let defaults: UserDefaults

    @Published var portRangeStart: Int {
        didSet { defaults.set(portRangeStart, forKey: Key.portRangeStart) }
    }

    @Published var portRangeEnd: Int {
        didSet { defaults.set(portRangeEnd, forKey: Key.portRangeEnd) }
    }

    @Published var refreshInterval: Double {
        didSet { defaults.set(refreshInterval, forKey: Key.refreshInterval) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        portRangeStart = defaults.object(forKey: Key.portRangeStart) as? Int
            ?? Default.portRangeStart
        portRangeEnd = defaults.object(forKey: Key.portRangeEnd) as? Int
            ?? Default.portRangeEnd
        refreshInterval = defaults.object(forKey: Key.refreshInterval) as? Double
            ?? Default.refreshInterval
    }

    /// Always a valid range, whatever order the two fields were typed in.
    var portRange: ClosedRange<Int> {
        let low = portRangeStart.clamped(to: Self.portBounds)
        let high = portRangeEnd.clamped(to: Self.portBounds)
        return min(low, high)...max(low, high)
    }

    var effectiveRefreshInterval: Double {
        refreshInterval.clamped(to: Self.intervalBounds)
    }

    func resetToDefaults() {
        portRangeStart = Default.portRangeStart
        portRangeEnd = Default.portRangeEnd
        refreshInterval = Default.refreshInterval
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
