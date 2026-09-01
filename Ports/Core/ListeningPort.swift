import Foundation

/// A single TCP port found in the LISTEN state, together with the process holding it.
struct ListeningPort: Identifiable, Hashable, Sendable {
    let port: Int
    let pid: pid_t
    /// Full process name. `lsof` is invoked with `+c 0` so this is not truncated.
    let processName: String
    /// User-supplied label from `~/.ports_labels.tsv`. Empty when unlabeled.
    var label: String

    init(port: Int, pid: pid_t, processName: String, label: String = "") {
        self.port = port
        self.pid = pid
        self.processName = processName
        self.label = label
    }

    /// A port can in principle be held by more than one PID (SO_REUSEPORT), so identity
    /// is the pair rather than the port alone.
    var id: String { "\(port)-\(pid)" }
}
