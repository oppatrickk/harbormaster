import Foundation

/// A single TCP port found in the LISTEN state, together with the process holding it.
///
/// This is purely what `lsof` reported. The user-facing label lives on `PortRow`, which pairs
/// a watched port with its listener (if any) — keeping labels in one place only.
struct ListeningPort: Identifiable, Hashable, Sendable {
    let port: Int
    let pid: pid_t
    /// Full process name. `lsof` is invoked with `+c 0` so this is not truncated.
    let processName: String

    /// A port can in principle be held by more than one PID (SO_REUSEPORT), so identity
    /// is the pair rather than the port alone.
    var id: String { "\(port)-\(pid)" }
}
