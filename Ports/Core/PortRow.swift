import Foundation

/// One row in the dropdown: a watched port, whether anything is currently listening on it,
/// and its label.
///
/// Every watched port produces a row whether or not it's in use, so idle ports stay visible
/// and labelable instead of disappearing from the list.
struct PortRow: Identifiable, Hashable, Sendable {
    let port: Int
    /// nil when nothing is listening — the port is free.
    let listener: ListeningPort?
    var label: String

    var id: Int { port }
    var isActive: Bool { listener != nil }

    var processName: String? { listener?.processName }
    var pid: pid_t? { listener?.pid }

    init(port: Int, listener: ListeningPort? = nil, label: String = "") {
        self.port = port
        self.listener = listener
        self.label = label
    }

    /// Builds one row per watched port, attaching any listener found for it.
    ///
    /// A port can in principle be held by more than one PID (SO_REUSEPORT); the lowest PID
    /// wins the row, since `listeners` arrives sorted by (port, pid).
    static func rows(
        watching ports: [Int],
        listeners: [ListeningPort],
        labels: [Int: String]
    ) -> [PortRow] {
        var byPort: [Int: ListeningPort] = [:]
        for listener in listeners where byPort[listener.port] == nil {
            byPort[listener.port] = listener
        }

        return ports.sorted().map { port in
            PortRow(port: port, listener: byPort[port], label: labels[port] ?? "")
        }
    }
}
