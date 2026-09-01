import Foundation
import Testing

@testable import Harbormaster

/// Fixtures below are verbatim captures of `lsof -nP -iTCP -sTCP:LISTEN -F pcn +c 0`
/// on macOS 26.6 / lsof 4.91 — not hand-written approximations.
struct PortScannerParsingTests {

    // MARK: - Fixtures

    /// Real capture of the 3000–3010 range with six Node dev servers running.
    static let devServers = """
        p61619
        cnode
        f47
        n[::1]:3001
        p63934
        cnode
        f46
        n[::1]:3002
        p69464
        cnode
        f54
        n[::1]:3003
        p70374
        cnode
        f47
        n[::1]:3004
        p71798
        cnode
        f46
        n[::1]:3005
        p76336
        cnode
        f53
        n[::1]:3007
        """

    /// Real capture showing multi-descriptor process blocks: `rapportd` holds one port on
    /// two fds, `ControlCenter` holds two ports on four fds.
    static let systemServices = """
        p641
        crapportd
        f10
        n*:63942
        f11
        n*:63942
        p711
        cControlCenter
        f9
        n*:7000
        f10
        n*:7000
        f11
        n*:5000
        f12
        n*:5000
        p904
        cfigma_agent
        f8
        n127.0.0.1:44950
        f10
        n127.0.0.1:44960
        p1095
        cCode Helper (Plugin)
        f35
        n127.0.0.1:65289
        f37
        n127.0.0.1:49154
        p2055
        clanguage_server_macos_arm
        f4
        n127.0.0.1:49162
        p2081
        cadb
        f12
        n127.0.0.1:5037
        """

    // MARK: - Core parsing

    @Test("Parses the default 3000–3010 range into one entry per dev server")
    func parsesDevServerRange() {
        let ports = PortScanner.parse(fieldOutput: Self.devServers, in: 3000...3010)

        #expect(ports.count == 6)
        #expect(ports.map(\.port) == [3001, 3002, 3003, 3004, 3005, 3007])
        #expect(ports.map(\.pid) == [61619, 63934, 69464, 70374, 71798, 76336])
        #expect(ports.allSatisfy { $0.processName == "node" })
    }

    @Test("Carries pid and command forward across a process block's file descriptors")
    func carriesProcessContextAcrossDescriptors() {
        // ControlCenter's 5000 entry appears three f/n pairs after its `c` line.
        let ports = PortScanner.parse(fieldOutput: Self.systemServices, in: 5000...5000)

        #expect(ports.count == 1)
        #expect(ports[0].pid == 711)
        #expect(ports[0].processName == "ControlCenter")
    }

    @Test("Collapses the duplicate IPv4/IPv6 rows a single process reports for one port")
    func dedupesDualStackListeners() {
        // rapportd reports *:63942 on both fd 10 and fd 11.
        let ports = PortScanner.parse(fieldOutput: Self.systemServices, in: 63942...63942)

        #expect(ports.count == 1)
        #expect(ports[0].pid == 641)
        #expect(ports[0].processName == "rapportd")
    }

    @Test("Keeps distinct ports held by the same process")
    func keepsDistinctPortsFromOneProcess() {
        let ports = PortScanner.parse(fieldOutput: Self.systemServices, in: 5000...7000)

        // ControlCenter holds 5000 and 7000; both survive dedup as separate entries.
        #expect(ports.filter { $0.pid == 711 }.map(\.port) == [5000, 7000])

        // adb's 5037 also falls inside this range — the whole range is returned, not just
        // one process's share of it.
        #expect(ports.map(\.port) == [5000, 5037, 7000])
    }

    @Test("Returns full, untruncated command names")
    func returnsUntruncatedCommandNames() {
        // The column output would have clipped these to `Code\x20H` and `language_`.
        let ports = PortScanner.parse(fieldOutput: Self.systemServices, in: 1...65535)
        let names = Dictionary(uniqueKeysWithValues: ports.map { ($0.port, $0.processName) })

        #expect(names[65289] == "Code Helper (Plugin)")
        #expect(names[49162] == "language_server_macos_arm")
    }

    @Test("Excludes ports outside the requested range")
    func filtersOutOfRangePorts() {
        let ports = PortScanner.parse(fieldOutput: Self.systemServices, in: 3000...3010)
        #expect(ports.isEmpty)
    }

    @Test("Results are sorted by port")
    func sortsByPort() {
        let ports = PortScanner.parse(fieldOutput: Self.systemServices, in: 1...65535)
        #expect(ports.map(\.port) == ports.map(\.port).sorted())
    }

    @Test("Empty output yields no ports — this is the lsof exit-code-1 case")
    func handlesEmptyOutput() {
        #expect(PortScanner.parse(fieldOutput: "", in: 3000...3010).isEmpty)
        #expect(PortScanner.parse(fieldOutput: "\n\n", in: 3000...3010).isEmpty)
    }

    @Test("Splits on CRLF as well as LF")
    func handlesCarriageReturnLineFeeds() {
        // Swift treats "\r\n" as a single grapheme cluster, so splitting on "\n" alone
        // would return the entire blob as one unparseable line.
        let crlf = "p61619\r\ncnode\r\nf47\r\nn[::1]:3001\r\n"
        let ports = PortScanner.parse(fieldOutput: crlf, in: 3000...3010)

        #expect(ports.count == 1)
        #expect(ports.first?.port == 3001)
        #expect(ports.first?.processName == "node")
    }

    @Test("Ignores name lines that appear before any process block")
    func ignoresOrphanedNameLines() {
        let orphaned = """
            n[::1]:3001
            f12
            """
        #expect(PortScanner.parse(fieldOutput: orphaned, in: 3000...3010).isEmpty)
    }

    // MARK: - Address forms

    @Test("Extracts the port from every address shape lsof emits", arguments: [
        ("[::1]:3001", 3001),               // IPv6 loopback, bracketed
        ("*:63942", 63942),                 // wildcard bind
        ("127.0.0.1:5037", 5037),           // IPv4 loopback
        ("[fe80::1%en0]:8080", 8080),       // IPv6 with zone index
        ("0.0.0.0:80", 80),
    ])
    func extractsPortFromAddress(address: String, expected: Int) {
        #expect(PortScanner.port(fromAddress: address) == expected)
    }

    @Test("Rejects addresses with no usable port", arguments: [
        "*:*",              // lsof's "any port" form
        "127.0.0.1",        // no colon at all
        "",
    ])
    func rejectsUnusableAddresses(address: String) {
        #expect(PortScanner.port(fromAddress: address) == nil)
    }

    // MARK: - Unescaping

    @Test("Unescapes lsof's escape sequences", arguments: [
        ("Code\\x20Helper\\x20(Plugin)", "Code Helper (Plugin)"),
        ("plain", "plain"),
        ("tab\\there", "tab\there"),
        ("back\\\\slash", "back\\slash"),
        ("trailing\\", "trailing\\"),        // lone trailing backslash, must not crash
        ("\\xZZbad", "\\xZZbad"),            // invalid hex passes through untouched
    ])
    func unescapesCommandNames(input: String, expected: String) {
        #expect(PortScanner.unescape(input) == expected)
    }

    // MARK: - Command construction

    @Test("Emits one -iTCP flag per watched port, sorted, and tolerates exit code 1")
    func buildsLsofInvocation() throws {
        let runner = StubCommandRunner(result: CommandResult(stdout: "", stderr: "", exitCode: 1))
        let ports = try PortScanner.scan(ports: [8080, 3000, 5432], runner: runner)

        #expect(ports.isEmpty)
        #expect(runner.recordedExecutable == "/usr/sbin/lsof")
        #expect(runner.recordedArguments == [
            "-nP",
            "-iTCP:3000", "-iTCP:5432", "-iTCP:8080",
            "-sTCP:LISTEN", "-F", "pcn", "+c", "0",
        ])
    }

    /// The single most dangerous edge case: `lsof` with no `-i` flag lists every open file on
    /// the system (~30k lines). An empty watch list must short-circuit before spawning.
    @Test("Never runs lsof when the watch list is empty")
    func doesNotRunLsofWithNoPorts() throws {
        let runner = StubCommandRunner(result: CommandResult(stdout: "", stderr: "", exitCode: 0))
        let ports = try PortScanner.scan(ports: [], runner: runner)

        #expect(ports.isEmpty)
        #expect(runner.callCount == 0)
    }

    @Test("Never runs lsof when every requested port is out of bounds")
    func doesNotRunLsofWithOnlyInvalidPorts() throws {
        let runner = StubCommandRunner(result: CommandResult(stdout: "", stderr: "", exitCode: 0))
        let ports = try PortScanner.scan(ports: [0, -1, 70000], runner: runner)

        #expect(ports.isEmpty)
        #expect(runner.callCount == 0)
    }

    @Test("Deduplicates repeated ports into a single flag")
    func deduplicatesRequestedPorts() throws {
        let runner = StubCommandRunner(result: CommandResult(stdout: "", stderr: "", exitCode: 1))
        _ = try PortScanner.scan(ports: [3000, 3000, 3000], runner: runner)

        #expect(runner.recordedArguments.filter { $0 == "-iTCP:3000" }.count == 1)
    }

    @Test("Drops out-of-bounds ports but still scans the valid ones")
    func filtersInvalidPortsFromInvocation() throws {
        let runner = StubCommandRunner(result: CommandResult(stdout: "", stderr: "", exitCode: 1))
        _ = try PortScanner.scan(ports: [0, 3000, 70000], runner: runner)

        #expect(runner.recordedArguments.filter { $0.hasPrefix("-iTCP:") } == ["-iTCP:3000"])
    }

    @Test("Throws on an lsof failure that isn't the nothing-matched case")
    func throwsOnRealFailure() {
        let runner = StubCommandRunner(
            result: CommandResult(stdout: "", stderr: "lsof: bad host", exitCode: 127)
        )
        #expect(throws: PortScannerError.self) {
            try PortScanner.scan(ports: [3000], runner: runner)
        }
    }

    @Test("Parses a successful scan end to end")
    func parsesSuccessfulScan() throws {
        let runner = StubCommandRunner(
            result: CommandResult(stdout: Self.devServers, stderr: "", exitCode: 0)
        )
        let ports = try PortScanner.scan(
            ports: [3001, 3002, 3003, 3004, 3005, 3007], runner: runner
        )

        #expect(ports.count == 6)
        #expect(ports.first?.port == 3001)
    }

    /// Real behavior confirmed against lsof 4.91: exit 1 means "at least one search term
    /// matched nothing", which with one -i per port happens whenever any port is idle —
    /// even though the other ports returned data that must still be parsed.
    @Test("Parses results that accompany exit code 1")
    func parsesResultsDespiteExitCodeOne() throws {
        let runner = StubCommandRunner(
            result: CommandResult(stdout: Self.devServers, stderr: "", exitCode: 1)
        )
        let ports = try PortScanner.scan(ports: [3001, 3002, 9999], runner: runner)

        #expect(ports.map(\.port) == [3001, 3002])
    }

    @Test("Only returns ports that were actually asked for")
    func filtersToRequestedPorts() throws {
        let runner = StubCommandRunner(
            result: CommandResult(stdout: Self.devServers, stderr: "", exitCode: 0)
        )
        let ports = try PortScanner.scan(ports: [3003, 3007], runner: runner)

        #expect(ports.map(\.port) == [3003, 3007])
    }

    @Test("Handles a non-contiguous watch list")
    func handlesNonContiguousPorts() {
        let ports = PortScanner.parse(
            fieldOutput: Self.systemServices, allowedPorts: [5000, 5037, 65289]
        )

        #expect(ports.map(\.port) == [5000, 5037, 65289])
        #expect(ports.map(\.processName) == ["ControlCenter", "adb", "Code Helper (Plugin)"])
    }
}

// MARK: - Test double

private final class StubCommandRunner: CommandRunner, @unchecked Sendable {
    private let result: CommandResult
    private(set) var recordedExecutable = ""
    private(set) var recordedArguments: [String] = []
    private(set) var callCount = 0

    init(result: CommandResult) {
        self.result = result
    }

    func run(_ executable: String, _ arguments: [String]) throws -> CommandResult {
        callCount += 1
        recordedExecutable = executable
        recordedArguments = arguments
        return result
    }
}
