import Foundation
import Testing

@testable import Ports

@MainActor
struct PreferencesTests {

    /// Each test gets an isolated UserDefaults suite so nothing touches real app settings.
    private func makeDefaults() -> UserDefaults {
        let name = "PortsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: - Defaults and persistence

    @Test("Fresh install watches 3000–3010 as individual ports")
    func defaultWatchList() {
        let preferences = Preferences(defaults: makeDefaults())

        #expect(preferences.watchedPorts == Array(3000...3010))
        #expect(preferences.watchedPorts.count == 11)
        #expect(preferences.refreshInterval == 3)
    }

    @Test("The watch list survives a relaunch")
    func persistsWatchList() {
        let defaults = makeDefaults()
        let first = Preferences(defaults: defaults)
        first.removePort(3005)
        first.addPort(8080)

        let second = Preferences(defaults: defaults)
        #expect(second.watchedPorts.contains(8080))
        #expect(!second.watchedPorts.contains(3005))
    }

    // MARK: - Migration from the old range setting

    @Test("An older contiguous range migrates to the individual ports it covered")
    func migratesLegacyRange() {
        let defaults = makeDefaults()
        defaults.set(4000, forKey: "portRangeStart")
        defaults.set(4004, forKey: "portRangeEnd")

        let preferences = Preferences(defaults: defaults)
        #expect(preferences.watchedPorts == [4000, 4001, 4002, 4003, 4004])
    }

    @Test("A reversed legacy range still migrates correctly")
    func migratesReversedLegacyRange() {
        let defaults = makeDefaults()
        defaults.set(4004, forKey: "portRangeStart")
        defaults.set(4000, forKey: "portRangeEnd")

        let preferences = Preferences(defaults: defaults)
        #expect(preferences.watchedPorts == [4000, 4001, 4002, 4003, 4004])
    }

    @Test("An explicit watch list wins over a stale legacy range")
    func explicitListBeatsLegacyRange() {
        let defaults = makeDefaults()
        defaults.set(4000, forKey: "portRangeStart")
        defaults.set(4004, forKey: "portRangeEnd")
        defaults.set([9000, 9001], forKey: "watchedPorts")

        let preferences = Preferences(defaults: defaults)
        #expect(preferences.watchedPorts == [9000, 9001])
    }

    // MARK: - Adding and removing

    @Test("Adding a port keeps the list sorted")
    func addKeepsSorted() {
        let preferences = Preferences(defaults: makeDefaults())
        preferences.resetToDefaults()
        preferences.addPort(80)
        preferences.addPort(9000)

        #expect(preferences.watchedPorts.first == 80)
        #expect(preferences.watchedPorts.last == 9000)
        #expect(preferences.watchedPorts == preferences.watchedPorts.sorted())
    }

    @Test("Adding a duplicate is rejected and doesn't grow the list")
    func rejectsDuplicates() {
        let preferences = Preferences(defaults: makeDefaults())
        let countBefore = preferences.watchedPorts.count

        #expect(preferences.addPort(3000) == false)
        #expect(preferences.watchedPorts.count == countBefore)
    }

    @Test("Out-of-bounds ports are rejected", arguments: [0, -1, 65536, 99999])
    func rejectsOutOfBoundsPorts(port: Int) {
        let preferences = Preferences(defaults: makeDefaults())

        #expect(preferences.addPort(port) == false)
        #expect(!preferences.watchedPorts.contains(port))
    }

    @Test("Boundary ports are accepted", arguments: [1, 65535])
    func acceptsBoundaryPorts(port: Int) {
        let preferences = Preferences(defaults: makeDefaults())

        #expect(preferences.addPort(port))
        #expect(preferences.watchedPorts.contains(port))
    }

    @Test("Removing a port drops exactly that one")
    func removeDropsOnePort() {
        let preferences = Preferences(defaults: makeDefaults())
        preferences.removePort(3005)

        #expect(!preferences.watchedPorts.contains(3005))
        #expect(preferences.watchedPorts.contains(3004))
        #expect(preferences.watchedPorts.contains(3006))
    }

    @Test("Removing an unwatched port is a no-op")
    func removeUnwatchedPortIsHarmless() {
        let preferences = Preferences(defaults: makeDefaults())
        let before = preferences.watchedPorts

        preferences.removePort(9999)
        #expect(preferences.watchedPorts == before)
    }

    @Test("The watch list can be emptied completely")
    func canEmptyWatchList() {
        let preferences = Preferences(defaults: makeDefaults())
        for port in preferences.watchedPorts {
            preferences.removePort(port)
        }

        #expect(preferences.watchedPorts.isEmpty)
    }

    @Test("A stored list with duplicates and junk is normalized on load")
    func normalizesStoredList() {
        let defaults = makeDefaults()
        defaults.set([3001, 3000, 3000, 0, 70000, 3002], forKey: "watchedPorts")

        let preferences = Preferences(defaults: defaults)
        #expect(preferences.watchedPorts == [3000, 3001, 3002])
    }

    /// `defaults write com.oppatrickk.Ports watchedPorts -array 3000 3001` stores *strings*.
    /// A plain `as? [Int]` cast fails on that, which would silently reset a hand-edited
    /// watch list back to the defaults.
    @Test("String-encoded ports from `defaults write -array` are accepted")
    func acceptsStringEncodedPorts() {
        let defaults = makeDefaults()
        defaults.set(["3003", "5432", "8080"], forKey: "watchedPorts")

        let preferences = Preferences(defaults: defaults)
        #expect(preferences.watchedPorts == [3003, 5432, 8080])
    }

    @Test("A mix of number- and string-encoded ports is accepted")
    func acceptsMixedEncodings() {
        let defaults = makeDefaults()
        defaults.set([3000, "3001", 3002], forKey: "watchedPorts")

        let preferences = Preferences(defaults: defaults)
        #expect(preferences.watchedPorts == [3000, 3001, 3002])
    }

    @Test("Unparseable entries are dropped individually, not fatally")
    func dropsUnparseableEntries() {
        let defaults = makeDefaults()
        defaults.set(["3000", "not-a-port", "3002"], forKey: "watchedPorts")

        let preferences = Preferences(defaults: defaults)
        #expect(preferences.watchedPorts == [3000, 3002])
    }

    /// "Watch nothing" is a legitimate choice — it must not spring back to the defaults.
    @Test("An explicitly empty stored list stays empty")
    func explicitlyEmptyListStaysEmpty() {
        let defaults = makeDefaults()
        defaults.set([Int](), forKey: "watchedPorts")

        let preferences = Preferences(defaults: defaults)
        #expect(preferences.watchedPorts.isEmpty)
    }

    @Test("An empty stored list wins over a legacy range")
    func emptyListBeatsLegacyRange() {
        let defaults = makeDefaults()
        defaults.set(4000, forKey: "portRangeStart")
        defaults.set(4004, forKey: "portRangeEnd")
        defaults.set([Int](), forKey: "watchedPorts")

        let preferences = Preferences(defaults: defaults)
        #expect(preferences.watchedPorts.isEmpty)
    }

    @Test("A non-array stored value falls through to the defaults")
    func nonArrayValueFallsThroughToDefaults() {
        let defaults = makeDefaults()
        defaults.set("garbage", forKey: "watchedPorts")

        let preferences = Preferences(defaults: defaults)
        #expect(preferences.watchedPorts == Array(3000...3010))
    }

    // MARK: - Refresh interval

    @Test("Refresh interval is clamped to sane bounds", arguments: [
        (0.0, 1.0), (0.5, 1.0), (3.0, 3.0), (60.0, 60.0), (999.0, 60.0),
    ])
    func clampsRefreshInterval(stored: Double, expected: Double) {
        let preferences = Preferences(defaults: makeDefaults())
        preferences.refreshInterval = stored

        #expect(preferences.effectiveRefreshInterval == expected)
    }

    @Test("Restoring defaults brings back the full default watch list")
    func restoreDefaults() {
        let preferences = Preferences(defaults: makeDefaults())
        preferences.removePort(3000)
        preferences.addPort(9999)
        preferences.refreshInterval = 30

        preferences.resetToDefaults()

        #expect(preferences.watchedPorts == Array(3000...3010))
        #expect(preferences.refreshInterval == 3)
    }
}
