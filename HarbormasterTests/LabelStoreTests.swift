import Foundation
import Testing

@testable import Harbormaster

/// The on-disk format is a compatibility contract with the existing `ports.sh` script,
/// so these tests assert on exact file bytes, not just round-tripping.
struct LabelStoreTests {

    /// Each test gets its own temp file; nothing here touches the real ~/.ports_labels.tsv.
    private func withTemporaryStore(
        seed: String? = nil,
        _ body: (LabelStore, URL) throws -> Void
    ) throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PortsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent(".ports_labels.tsv")
        if let seed {
            try seed.write(to: url, atomically: true, encoding: .utf8)
        }
        try body(LabelStore(url: url), url)
    }

    private func contents(of url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Format

    @Test("Writes exactly <port>\\t<label>\\n")
    func writesTabSeparatedLines() throws {
        try withTemporaryStore { store, url in
            try store.setLabel("api", for: 3000)
            #expect(try contents(of: url) == "3000\tapi\n")
        }
    }

    @Test("Writes one line per port, sorted ascending")
    func writesSortedLines() throws {
        try withTemporaryStore { store, url in
            try store.setLabel("docs", for: 3010)
            try store.setLabel("api", for: 3000)
            try store.setLabel("web", for: 3001)

            #expect(try contents(of: url) == "3000\tapi\n3001\tweb\n3010\tdocs\n")
        }
    }

    @Test("Reads a file written by the bash script")
    func readsExternallyWrittenFile() throws {
        try withTemporaryStore(seed: "3000\tapi\n3001\tweb\n") { store, _ in
            #expect(store.load() == [3000: "api", 3001: "web"])
        }
    }

    @Test("Missing file reads as no labels rather than failing")
    func missingFileLoadsEmpty() throws {
        try withTemporaryStore { store, _ in
            #expect(store.load().isEmpty)
        }
    }

    // MARK: - Tolerance for hand-edited files

    @Test("Skips blank and malformed lines instead of failing the whole load")
    func skipsMalformedLines() throws {
        let seed = """
            3000\tapi

            no-tab-here
            notaport\tlabel
            3001\tweb

            """
        try withTemporaryStore(seed: seed) { store, _ in
            #expect(store.load() == [3000: "api", 3001: "web"])
        }
    }

    @Test("Handles CRLF line endings")
    func handlesCarriageReturns() throws {
        try withTemporaryStore(seed: "3000\tapi\r\n3001\tweb\r\n") { store, _ in
            #expect(store.load() == [3000: "api", 3001: "web"])
        }
    }

    @Test("Preserves labels containing spaces")
    func preservesSpacesInLabels() throws {
        try withTemporaryStore { store, url in
            try store.setLabel("my api server", for: 3000)
            #expect(try contents(of: url) == "3000\tmy api server\n")
            #expect(store.load()[3000] == "my api server")
        }
    }

    @Test("Splits on the first tab, so a label containing tabs round-trips")
    func splitsOnFirstTabOnly() throws {
        try withTemporaryStore(seed: "3000\tapi\tv2\n") { store, _ in
            #expect(store.load() == [3000: "api\tv2"])
        }
    }

    @Test("Collapses newlines in a label so the line format can't be broken")
    func sanitizesNewlinesInLabels() throws {
        try withTemporaryStore { store, url in
            try store.setLabel("api\nserver", for: 3000)

            let text = try contents(of: url)
            #expect(text == "3000\tapi server\n")
            #expect(text.filter { $0 == "\n" }.count == 1)
        }
    }

    @Test("Trims surrounding whitespace from labels")
    func trimsLabels() throws {
        try withTemporaryStore { store, url in
            try store.setLabel("  api  ", for: 3000)
            #expect(try contents(of: url) == "3000\tapi\n")
        }
    }

    // MARK: - Removal

    @Test("Clearing a label removes its line entirely")
    func clearingLabelRemovesLine() throws {
        try withTemporaryStore(seed: "3000\tapi\n3001\tweb\n") { store, url in
            try store.setLabel("", for: 3000)

            #expect(try contents(of: url) == "3001\tweb\n")
            #expect(store.load()[3000] == nil)
        }
    }

    @Test("A whitespace-only label is treated as cleared")
    func whitespaceOnlyLabelRemovesLine() throws {
        try withTemporaryStore(seed: "3000\tapi\n") { store, url in
            try store.setLabel("   ", for: 3000)
            #expect(try contents(of: url) == "")
        }
    }

    @Test("removeLabel drops the line, as when a port is killed")
    func removeLabelDropsLine() throws {
        try withTemporaryStore(seed: "3000\tapi\n3001\tweb\n") { store, url in
            try store.removeLabel(for: 3001)
            #expect(try contents(of: url) == "3000\tapi\n")
        }
    }

    @Test("Removing an unlabeled port is a no-op, not an error")
    func removingUnknownPortIsHarmless() throws {
        try withTemporaryStore(seed: "3000\tapi\n") { store, url in
            try store.removeLabel(for: 9999)
            #expect(try contents(of: url) == "3000\tapi\n")
        }
    }

    @Test("Removing the last label leaves an empty file, not a stray newline")
    func removingLastLabelEmptiesFile() throws {
        try withTemporaryStore(seed: "3000\tapi\n") { store, url in
            try store.removeLabel(for: 3000)
            #expect(try contents(of: url) == "")
        }
    }

    // MARK: - Coexistence with ports.sh

    @Test("Updating one port preserves the others")
    func updatePreservesOtherPorts() throws {
        try withTemporaryStore(seed: "3000\tapi\n3001\tweb\n3002\tdocs\n") { store, url in
            try store.setLabel("api-v2", for: 3001)
            #expect(try contents(of: url) == "3000\tapi\n3001\tapi-v2\n3002\tdocs\n")
        }
    }

    @Test("Re-reads before writing, so an external edit isn't clobbered")
    func doesNotClobberExternalEdits() throws {
        try withTemporaryStore(seed: "3000\tapi\n") { store, url in
            _ = store.load()

            // Simulate ports.sh adding a line behind our back between refreshes.
            try "3000\tapi\n3005\tadded-by-script\n"
                .write(to: url, atomically: true, encoding: .utf8)

            try store.setLabel("worker", for: 3009)

            #expect(try contents(of: url) ==
                "3000\tapi\n3005\tadded-by-script\n3009\tworker\n")
        }
    }
}
