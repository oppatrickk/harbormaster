import Foundation

/// Reads and writes `~/.ports_labels.tsv`.
///
/// The format is fixed by compatibility with the existing `ports.sh` script: one
/// `<port>\t<label>` line per labeled port, newline terminated. Both tools read and write
/// this file, so every mutation re-reads before rewriting rather than caching state — an
/// edit made by the script between refreshes must not be clobbered.
/// Thread-safe: all file access is serialized through `queue`, and `url` is immutable.
final class LabelStore: @unchecked Sendable {
    static let defaultURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".ports_labels.tsv")

    private let url: URL
    private let queue = DispatchQueue(label: "com.oppatrickk.Ports.LabelStore")

    init(url: URL = LabelStore.defaultURL) {
        self.url = url
    }

    var fileURL: URL { url }

    /// All labels keyed by port. A missing or unreadable file is simply "no labels".
    func load() -> [Int: String] {
        queue.sync { readUnlocked() }
    }

    /// Sets a port's label, or removes the line entirely if the label is blank.
    func setLabel(_ label: String, for port: Int) throws {
        try queue.sync {
            var labels = readUnlocked()
            let cleaned = sanitize(label)
            if cleaned.isEmpty {
                labels.removeValue(forKey: port)
            } else {
                labels[port] = cleaned
            }
            try writeUnlocked(labels)
        }
    }

    /// Removes a port's line. Called when a port is killed or its label is cleared.
    func removeLabel(for port: Int) throws {
        try queue.sync {
            var labels = readUnlocked()
            guard labels.removeValue(forKey: port) != nil else { return }
            try writeUnlocked(labels)
        }
    }

    // MARK: - Private

    private func readUnlocked() -> [Int: String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }

        var labels: [Int: String] = [:]
        // Split on `isNewline`, not on "\n": Swift treats CRLF as a single grapheme cluster,
        // so `split(separator: "\n")` silently fails to break a CRLF file into lines at all.
        for row in text.split(whereSeparator: \.isNewline) {
            // Skip anything that isn't `<int>\t<something>` rather than failing the whole
            // load — this file is hand-editable and shared with ports.sh.
            guard let tab = row.firstIndex(of: "\t"),
                  let port = Int(row[row.startIndex..<tab])
            else { continue }

            // Split on the *first* tab only, so a label containing tabs still round-trips.
            labels[port] = String(row[row.index(after: tab)...])
        }
        return labels
    }

    private func writeUnlocked(_ labels: [Int: String]) throws {
        // Sorted by port so the file stays diff-stable across writes from either tool.
        let body = labels.keys.sorted()
            .compactMap { port -> String? in
                guard let label = labels[port] else { return nil }
                return "\(port)\t\(label)"
            }
            .joined(separator: "\n")

        let text = body.isEmpty ? "" : body + "\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Newlines would break the one-line-per-port format, so they collapse to spaces.
    /// Interior tabs are left alone — `readUnlocked` splits on the first tab only.
    private func sanitize(_ label: String) -> String {
        label
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
