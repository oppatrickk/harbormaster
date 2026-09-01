import Foundation
import Testing

@testable import Ports

/// Auto-detected labels come from each process's working directory. Fixtures are verbatim
/// captures of `lsof -a -p <pids> -d cwd -F pn` on macOS.
struct ProcessDirectoryTests {

    /// Real capture: a vite dev server in a project directory, plus daemons running from /.
    static let capture = """
        p55582
        fcwd
        n/Users/johnpatrickprieto/Documents/Work/streamline_mes_due_soon
        p2081
        fcwd
        n/Users/johnpatrickprieto/fvm/versions/3.41.2
        p47041
        fcwd
        n/
        p52893
        fcwd
        n/
        """

    // MARK: - Parsing

    @Test("Maps each PID to its working directory's basename")
    func mapsPIDsToProjectNames() {
        let names = ProcessDirectory.parse(fieldOutput: Self.capture)

        #expect(names[55582] == "streamline_mes_due_soon")
        #expect(names[2081] == "3.41.2")
    }

    @Test("Processes running from / produce no name")
    func skipsRootWorkingDirectories() {
        let names = ProcessDirectory.parse(fieldOutput: Self.capture)

        #expect(names[47041] == nil)
        #expect(names[52893] == nil)
    }

    @Test("Carries the PID forward across the fcwd line")
    func carriesPIDAcrossDescriptorLine() {
        // The n line arrives one line after fcwd, not immediately after p.
        let names = ProcessDirectory.parse(fieldOutput: "p123\nfcwd\nn/tmp/myproject")
        #expect(names[123] == "myproject")
    }

    @Test("Empty output yields no names")
    func handlesEmptyOutput() {
        #expect(ProcessDirectory.parse(fieldOutput: "").isEmpty)
    }

    @Test("A path line before any PID block is ignored")
    func ignoresOrphanedPaths() {
        #expect(ProcessDirectory.parse(fieldOutput: "n/tmp/orphan").isEmpty)
    }

    // MARK: - Name extraction

    @Test("Extracts the trailing directory name", arguments: [
        ("/Users/me/Work/my-shop", "my-shop"),
        ("/tmp/proj", "proj"),
        ("/Users/me/code/api_v2", "api_v2"),
        ("/Users/me/code/with space", "with space"),
    ])
    func extractsTrailingName(path: String, expected: String) {
        #expect(ProcessDirectory.projectName(fromPath: path) == expected)
    }

    /// Neither "/" nor the bare home directory says anything about what a port is serving.
    @Test("Rejects paths that don't name a project", arguments: [
        "/",
        "",
        "relative/path",
    ])
    func rejectsUninformativePaths(path: String) {
        #expect(ProcessDirectory.projectName(fromPath: path) == nil)
    }

    @Test("Rejects the bare home directory")
    func rejectsHomeDirectory() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(ProcessDirectory.projectName(fromPath: home) == nil)
    }

    // MARK: - Invocation

    @Test("Batches all PIDs into a single comma-separated lsof call")
    func batchesPIDsIntoOneCall() throws {
        let runner = RecordingRunner(result: CommandResult(stdout: "", stderr: "", exitCode: 0))
        _ = try ProcessDirectory.projectNames(for: [300, 100, 200], runner: runner)

        #expect(runner.callCount == 1)
        #expect(runner.recordedArguments == ["-a", "-p", "100,200,300", "-d", "cwd", "-F", "pn"])
    }

    /// Same hazard as the port scan: `lsof -a -d cwd` with no -p walks every process.
    @Test("Never runs lsof with no PIDs")
    func doesNotRunLsofWithNoPIDs() throws {
        let runner = RecordingRunner(result: CommandResult(stdout: "", stderr: "", exitCode: 0))

        #expect(try ProcessDirectory.projectNames(for: [], runner: runner).isEmpty)
        #expect(try ProcessDirectory.projectNames(for: [0, -1], runner: runner).isEmpty)
        #expect(runner.callCount == 0)
    }

    @Test("Tolerates exit code 1 from PIDs that matched nothing")
    func toleratesExitCodeOne() throws {
        let runner = RecordingRunner(
            result: CommandResult(stdout: Self.capture, stderr: "", exitCode: 1)
        )
        let names = try ProcessDirectory.projectNames(for: [55582], runner: runner)

        #expect(names[55582] == "streamline_mes_due_soon")
    }

    @Test("A hard lsof failure yields no names rather than throwing")
    func failureYieldsNoNames() throws {
        let runner = RecordingRunner(
            result: CommandResult(stdout: "", stderr: "boom", exitCode: 127)
        )
        #expect(try ProcessDirectory.projectNames(for: [1], runner: runner).isEmpty)
    }
}

private final class RecordingRunner: CommandRunner, @unchecked Sendable {
    private let result: CommandResult
    private(set) var recordedArguments: [String] = []
    private(set) var callCount = 0

    init(result: CommandResult) { self.result = result }

    func run(_ executable: String, _ arguments: [String]) throws -> CommandResult {
        callCount += 1
        recordedArguments = arguments
        return result
    }
}
