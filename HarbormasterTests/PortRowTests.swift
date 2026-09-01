import Foundation
import Testing

@testable import Harbormaster

/// Rows are built for *every* watched port, not just the ones in use, so idle ports stay
/// visible and labelable.
struct PortRowTests {

    private func listener(_ port: Int, _ pid: pid_t, _ name: String = "node") -> ListeningPort {
        ListeningPort(port: port, pid: pid, processName: name)
    }

    @Test("Produces one row per watched port, active or not")
    func rowPerWatchedPort() {
        let rows = PortRow.rows(
            watching: [3000, 3001, 3002],
            listeners: [listener(3001, 61619)],
            labels: [:]
        )

        #expect(rows.map(\.port) == [3000, 3001, 3002])
        #expect(rows.map(\.isActive) == [false, true, false])
    }

    @Test("An idle port has no listener, process name, or PID")
    func idlePortHasNoListener() {
        let rows = PortRow.rows(watching: [3000], listeners: [], labels: [:])

        #expect(rows.count == 1)
        #expect(rows[0].isActive == false)
        #expect(rows[0].listener == nil)
        #expect(rows[0].processName == nil)
        #expect(rows[0].pid == nil)
    }

    @Test("An active port carries its process name and PID")
    func activePortCarriesProcessDetails() {
        let rows = PortRow.rows(
            watching: [3001],
            listeners: [listener(3001, 61619, "node")],
            labels: [:]
        )

        #expect(rows[0].isActive)
        #expect(rows[0].processName == "node")
        #expect(rows[0].pid == 61619)
    }

    @Test("Rows are sorted by port regardless of watch-list order")
    func sortsByPort() {
        let rows = PortRow.rows(
            watching: [8080, 3000, 5432],
            listeners: [],
            labels: [:]
        )

        #expect(rows.map(\.port) == [3000, 5432, 8080])
    }

    @Test("Handles a non-contiguous watch list")
    func handlesNonContiguousPorts() {
        let rows = PortRow.rows(
            watching: [3000, 5432, 8080],
            listeners: [listener(5432, 900, "postgres")],
            labels: [:]
        )

        #expect(rows.map(\.port) == [3000, 5432, 8080])
        #expect(rows.map(\.isActive) == [false, true, false])
        #expect(rows[1].processName == "postgres")
    }

    @Test("Labels attach to the right port")
    func attachesLabels() {
        let rows = PortRow.rows(
            watching: [3000, 3001],
            listeners: [listener(3001, 61619)],
            labels: [3000: "reserved", 3001: "storefront"]
        )

        #expect(rows[0].label == "reserved")
        #expect(rows[1].label == "storefront")
    }

    @Test("An idle port can still carry a label")
    func idlePortKeepsItsLabel() {
        let rows = PortRow.rows(watching: [3000], listeners: [], labels: [3000: "reserved"])

        #expect(rows[0].isActive == false)
        #expect(rows[0].label == "reserved")
    }

    @Test("Ports with no label get an empty string, not nil")
    func unlabeledPortsGetEmptyLabel() {
        let rows = PortRow.rows(watching: [3000], listeners: [], labels: [:])
        #expect(rows[0].label.isEmpty)
    }

    @Test("A listener on an unwatched port is ignored")
    func ignoresListenersOutsideTheWatchList() {
        let rows = PortRow.rows(
            watching: [3000],
            listeners: [listener(9999, 123)],
            labels: [:]
        )

        #expect(rows.map(\.port) == [3000])
        #expect(rows[0].isActive == false)
    }

    @Test("Labels for unwatched ports don't create rows")
    func ignoresLabelsOutsideTheWatchList() {
        let rows = PortRow.rows(watching: [3000], listeners: [], labels: [9999: "stale"])
        #expect(rows.map(\.port) == [3000])
    }

    @Test("When two PIDs hold one port, the lowest PID wins the row")
    func collapsesMultiplePIDsOnOnePort() {
        // SO_REUSEPORT makes this possible; PortScanner returns them sorted by (port, pid).
        let rows = PortRow.rows(
            watching: [3000],
            listeners: [listener(3000, 100, "first"), listener(3000, 200, "second")],
            labels: [:]
        )

        #expect(rows.count == 1)
        #expect(rows[0].pid == 100)
        #expect(rows[0].processName == "first")
    }

    @Test("An empty watch list produces no rows")
    func emptyWatchListProducesNoRows() {
        #expect(PortRow.rows(watching: [], listeners: [], labels: [:]).isEmpty)
    }

    @Test("Row identity is the port number")
    func identityIsPort() {
        let rows = PortRow.rows(watching: [3000], listeners: [], labels: [:])
        #expect(rows[0].id == 3000)
    }

    // MARK: - Display formatting

    /// SwiftUI treats `Text("\(anInt)")` as a LocalizedStringKey and applies locale number
    /// formatting, which rendered port 3000 as "3,000" and PID 61619 as "PID 61,619" in the
    /// shipping UI. Ports and PIDs are identifiers and must never be group-separated.
    @Test("Port text has no thousands separator", arguments: [
        (80, "80"), (3000, "3000"), (5432, "5432"), (8080, "8080"), (65535, "65535"),
    ])
    func portTextIsUngrouped(port: Int, expected: String) {
        let row = PortRow(port: port)

        #expect(row.portText == expected)
        #expect(!row.portText.contains(","))
        #expect(!row.portText.contains("."))
    }

    @Test("PID text has no thousands separator")
    func pidTextIsUngrouped() {
        let row = PortRow(port: 3001, listener: listener(3001, 61619))

        #expect(row.pidText == "PID 61619")
        #expect(row.pidText?.contains(",") == false)
    }

    @Test("An idle row has no PID text")
    func idleRowHasNoPIDText() {
        #expect(PortRow(port: 3000).pidText == nil)
    }

    // MARK: - Auto-detected labels

    @Test("An active port picks up the detected project name for its PID")
    func attachesAutoLabelByPID() {
        let rows = PortRow.rows(
            watching: [3000],
            listeners: [listener(3000, 55582)],
            labels: [:],
            autoLabels: [55582: "streamline_mes_due_soon"]
        )

        #expect(rows[0].autoLabel == "streamline_mes_due_soon")
        #expect(rows[0].labelPlaceholder == "streamline_mes_due_soon")
    }

    @Test("An idle port has no auto-label — there's no process to detect from")
    func idlePortHasNoAutoLabel() {
        let rows = PortRow.rows(
            watching: [3000], listeners: [], labels: [:], autoLabels: [55582: "shop"]
        )

        #expect(rows[0].autoLabel == nil)
        #expect(rows[0].labelPlaceholder == "Label")
    }

    @Test("A detected name for an unrelated PID isn't applied")
    func ignoresAutoLabelForOtherPIDs() {
        let rows = PortRow.rows(
            watching: [3000],
            listeners: [listener(3000, 111)],
            labels: [:],
            autoLabels: [999: "other-project"]
        )

        #expect(rows[0].autoLabel == nil)
    }

    /// The typed label is the real value; the detected name only fills the empty field.
    @Test("A manual label coexists with the detected name and wins for display")
    func manualLabelWinsOverAutoLabel() {
        let rows = PortRow.rows(
            watching: [3000],
            listeners: [listener(3000, 55582)],
            labels: [3000: "storefront"],
            autoLabels: [55582: "streamline_mes_due_soon"]
        )

        #expect(rows[0].label == "storefront")
        #expect(rows[0].autoLabel == "streamline_mes_due_soon")
    }

    @Test("Falls back to a generic placeholder with nothing detected")
    func genericPlaceholderWithoutDetection() {
        let rows = PortRow.rows(watching: [3000], listeners: [listener(3000, 1)], labels: [:])
        #expect(rows[0].labelPlaceholder == "Label")
    }
}
