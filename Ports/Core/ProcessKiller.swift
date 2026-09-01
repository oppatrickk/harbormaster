import Foundation

enum KillError: Error, LocalizedError {
    /// The process belongs to another user. This tool never elevates privileges.
    case notPermitted(pid_t)
    case invalidPID(pid_t)
    case failed(pid_t, code: Int32)

    var errorDescription: String? {
        switch self {
        case let .notPermitted(pid):
            return "Not permitted to kill PID \(pid) — it belongs to another user."
        case let .invalidPID(pid):
            return "Refusing to signal PID \(pid)."
        case let .failed(pid, code):
            return "Could not kill PID \(pid): \(String(cString: strerror(code)))."
        }
    }
}

enum ProcessKiller {
    /// Sends SIGKILL to a single process.
    ///
    /// `ESRCH` (no such process) is treated as success: the process is already gone, which
    /// is exactly the outcome the caller wanted.
    static func kill(pid: pid_t) throws {
        // Guard hard. kill(0, …) signals the entire process group and kill(-1, …) signals
        // every process the user owns — neither is ever what we mean here.
        guard pid > 0 else { throw KillError.invalidPID(pid) }

        if Darwin.kill(pid, SIGKILL) == 0 { return }

        switch errno {
        case ESRCH: return
        case EPERM: throw KillError.notPermitted(pid)
        case let code: throw KillError.failed(pid, code: code)
        }
    }
}
