import Foundation

/// Resolves a running process to the project it's serving, by looking at its working
/// directory.
///
/// A dev server started in `~/Work/streamline_mes_due_soon` reports that as its cwd, so the
/// directory's basename is a good guess at what the port is for. This is only ever used as a
/// placeholder — it is never written to `~/.ports_labels.tsv`, so the file shared with
/// `ports.sh` stays limited to labels the user actually typed.
enum ProcessDirectory {

    /// Working directory basenames keyed by PID. PIDs whose cwd isn't meaningful (or isn't
    /// readable, e.g. another user's process) are simply absent from the result.
    static func projectNames(
        for pids: [pid_t],
        runner: CommandRunner = SystemCommandRunner()
    ) throws -> [pid_t: String] {
        let unique = Set(pids.filter { $0 > 0 })

        // Same hazard as the port scan: `lsof -a -d cwd` with no -p would walk every process
        // on the system.
        guard !unique.isEmpty else { return [:] }

        let list = unique.sorted().map(String.init).joined(separator: ",")
        let result = try runner.run(PortScanner.lsofPath, [
            "-a",                   // AND the selections rather than OR-ing them
            "-p", list,             // comma-separated PIDs in one call
            "-d", "cwd",            // just the working directory descriptor
            "-F", "pn",             // machine-readable: pid, name
        ])

        // As with the port scan, exit 1 means some PID matched nothing — not a failure.
        guard result.exitCode == 0 || result.exitCode == 1 else { return [:] }
        return parse(fieldOutput: result.stdout)
    }

    /// Parses `lsof -d cwd -F pn` output. Stateful in the same way as the port scan: a
    /// `p<pid>` line opens a block and the following `n<path>` belongs to it.
    static func parse(fieldOutput: String) -> [pid_t: String] {
        var names: [pid_t: String] = [:]
        var currentPID: pid_t?

        for line in fieldOutput.split(whereSeparator: \.isNewline) {
            guard let field = line.first else { continue }
            let value = String(line.dropFirst())

            switch field {
            case "p":
                currentPID = pid_t(value)
            case "n":
                guard let pid = currentPID, let name = projectName(fromPath: value) else {
                    continue
                }
                names[pid] = name
            default:
                continue    // f, and anything else we don't need
            }
        }
        return names
    }

    /// The basename of a working directory, when it plausibly names a project.
    ///
    /// Daemons commonly run from `/`, and a shell started in the home directory tells us
    /// nothing — neither is worth showing as a label.
    static func projectName(fromPath path: String) -> String? {
        guard path.hasPrefix("/"), path != "/" else { return nil }
        guard path != FileManager.default.homeDirectoryForCurrentUser.path else { return nil }

        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? nil : name
    }
}
