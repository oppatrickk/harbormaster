import Foundation

// MARK: - Command execution

struct CommandResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

/// Indirection over process spawning so the scanner can be exercised in tests
/// without actually running `lsof`.
protocol CommandRunner: Sendable {
    func run(_ executable: String, _ arguments: [String]) throws -> CommandResult
}

struct SystemCommandRunner: CommandRunner {
    func run(_ executable: String, _ arguments: [String]) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            throw PortScannerError.launchFailed(executable: executable, underlying: error)
        }

        // Drain both pipes concurrently. Reading one to completion before the other can
        // deadlock if the process fills the other pipe's buffer while we're blocked.
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "PortScanner.pipe", attributes: .concurrent)

        queue.async(group: group) { outData = outPipe.fileHandleForReading.readDataToEndOfFile() }
        queue.async(group: group) { errData = errPipe.fileHandleForReading.readDataToEndOfFile() }
        group.wait()
        process.waitUntilExit()

        return CommandResult(
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }
}

// MARK: - Errors

enum PortScannerError: Error, LocalizedError {
    case launchFailed(executable: String, underlying: Error)
    case lsofFailed(exitCode: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case let .launchFailed(executable, underlying):
            return "Could not run \(executable): \(underlying.localizedDescription)"
        case let .lsofFailed(exitCode, stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? "lsof exited with code \(exitCode)."
                : "lsof exited with code \(exitCode): \(detail)"
        }
    }
}

// MARK: - Scanner

enum PortScanner {
    static let lsofPath = "/usr/sbin/lsof"

    /// Scans `range` for listening TCP sockets.
    ///
    /// Uses `lsof`'s field output (`-F pcn`) rather than the human-readable columns: the
    /// default `COMMAND` column is truncated to 9 characters, which mangles names like
    /// `language_server_macos_arm`. `+c 0` lifts that limit.
    static func scan(
        range: ClosedRange<Int>,
        runner: CommandRunner = SystemCommandRunner()
    ) throws -> [ListeningPort] {
        let spec = range.lowerBound == range.upperBound
            ? "\(range.lowerBound)"
            : "\(range.lowerBound)-\(range.upperBound)"

        let result = try runner.run(lsofPath, [
            "-nP",                  // no DNS / no port-name lookup
            "-iTCP:\(spec)",
            "-sTCP:LISTEN",
            "-F", "pcn",            // machine-readable: pid, command, name
            "+c", "0",              // don't truncate command names
        ])

        // lsof exits 1 when it simply found nothing — the common case for a quiet range.
        // Treating that as an error would surface a permanent failure whenever no dev
        // servers are running.
        guard result.exitCode == 0 || result.exitCode == 1 else {
            throw PortScannerError.lsofFailed(exitCode: result.exitCode, stderr: result.stderr)
        }

        return parse(fieldOutput: result.stdout, in: range)
    }

    /// Parses `lsof -F pcn` output. Pure — this is the unit-tested core.
    ///
    /// The format is stateful: a `p<pid>` line opens a process block and `c<command>` names
    /// it, then *several* `f<fd>`/`n<address>` pairs may follow, all belonging to that same
    /// process. So pid/command are carried forward until the next `p` line.
    ///
    ///     p641
    ///     crapportd
    ///     f10
    ///     n*:63942
    ///     f11
    ///     n*:63942      <- same process, same port, second file descriptor
    static func parse(fieldOutput: String, in range: ClosedRange<Int>) -> [ListeningPort] {
        var results: [ListeningPort] = []
        var seen = Set<String>()
        var currentPID: pid_t?
        var currentCommand = ""

        // `isNewline` rather than "\n" — Swift treats CRLF as one grapheme cluster, so
        // splitting on "\n" alone would fail to break the output into lines.
        for line in fieldOutput.split(whereSeparator: \.isNewline) {
            guard let field = line.first else { continue }
            let value = String(line.dropFirst())

            switch field {
            case "p":
                currentPID = pid_t(value)
                currentCommand = ""
            case "c":
                currentCommand = unescape(value)
            case "n":
                guard let pid = currentPID,
                      let port = port(fromAddress: value),
                      range.contains(port)
                else { continue }

                // A process listening on both IPv4 and IPv6 yields one entry per socket.
                guard seen.insert("\(port)-\(pid)").inserted else { continue }
                results.append(
                    ListeningPort(port: port, pid: pid, processName: currentCommand)
                )
            default:
                continue    // f, t, and any other field we don't need
            }
        }

        return results.sorted {
            ($0.port, $0.pid) < ($1.port, $1.pid)
        }
    }

    /// Extracts the port from an `lsof` address.
    ///
    /// Handles the three shapes macOS emits: `[::1]:3001`, `*:63942`, `127.0.0.1:5037`.
    /// Splitting on the *last* colon covers all of them, including bracketed IPv6.
    static func port(fromAddress address: String) -> Int? {
        // Defensive: peer addresses (`local->remote`) shouldn't appear under -sTCP:LISTEN,
        // but if one does, only the local side is meaningful.
        let local = address.components(separatedBy: "->").first ?? address
        guard let colon = local.lastIndex(of: ":") else { return nil }
        return Int(local[local.index(after: colon)...])
    }

    /// Reverses `lsof`'s escaping of non-printable characters (`\xHH`, `\n`, `\r`, `\t`, `\\`).
    ///
    /// In field mode spaces come through literally — `cCode Helper (Plugin)` — but control
    /// characters are still escaped, and the column mode this replaces escaped spaces too.
    static func unescape(_ input: String) -> String {
        guard input.contains("\\") else { return input }

        var output = ""
        var index = input.startIndex

        while index < input.endIndex {
            let character = input[index]
            let next = input.index(after: index)

            if character == "\\", next < input.endIndex {
                switch input[next] {
                case "x":
                    let hexStart = input.index(next, offsetBy: 1)
                    if let hexEnd = input.index(hexStart, offsetBy: 2, limitedBy: input.endIndex),
                       let byte = UInt8(input[hexStart..<hexEnd], radix: 16) {
                        output.append(Character(UnicodeScalar(byte)))
                        index = hexEnd
                        continue
                    }
                case "n":
                    output.append("\n"); index = input.index(after: next); continue
                case "r":
                    output.append("\r"); index = input.index(after: next); continue
                case "t":
                    output.append("\t"); index = input.index(after: next); continue
                case "\\":
                    output.append("\\"); index = input.index(after: next); continue
                default:
                    break
                }
            }

            output.append(character)
            index = next
        }

        return output
    }
}
