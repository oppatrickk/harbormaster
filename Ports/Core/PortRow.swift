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

    /// Display strings built with `String(_:)` rather than interpolated into a `Text` literal.
    ///
    /// SwiftUI treats `Text("\(someInt)")` as a LocalizedStringKey and applies locale number
    /// formatting to it, which renders port 3000 as "3,000" and PID 61619 as "61,619".
    /// Identifiers must never be group-separated, so the formatting happens here and the
    /// views render it with `Text(verbatim:)`.
    var portText: String { String(port) }

    var pidText: String? { pid.map { "PID " + String($0) } }

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
