import Foundation
import Testing
@testable import SvnKit

@Test func logEntryCodableRoundTrip() throws {
    let entry = SvnLogEntry(
        revision: 42,
        author: "alice",
        date: Date(timeIntervalSince1970: 1_700_000_000),
        message: "fix bug",
        changedPaths: [
            SvnChangedPath(action: .modified, path: "/trunk/a.txt", kind: "file")
        ]
    )
    let data = try JSONEncoder().encode(entry)
    let decoded = try JSONDecoder().decode(SvnLogEntry.self, from: data)
    #expect(decoded == entry)
}
