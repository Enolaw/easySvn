import Foundation

/// 解析 `svn list --xml` 的输出。
///
/// 输出结构示例：
/// ```xml
/// <lists>
///   <list path="file:///tmp/repo">
///     <entry kind="file">
///       <name>foo.txt</name>
///       <size>5</size>
///       <commit revision="1"><author>alice</author><date>...</date></commit>
///     </entry>
///   </list>
/// </lists>
/// ```
public enum ListXMLParser {

    public static func parse(_ data: Data) throws -> [SvnListEntry] {
        let document: XMLDocument
        do {
            document = try XMLDocument(data: data)
        } catch {
            throw SvnKitError.xmlParseFailed("list XML 无法解析: \(error.localizedDescription)")
        }

        let entryNodes = try document.nodes(forXPath: "/lists/list/entry")
        return try entryNodes.compactMap { $0 as? XMLElement }.map(parseEntry(_:))
    }

    private static func parseEntry(_ entry: XMLElement) throws -> SvnListEntry {
        guard
            let kindRaw = entry.attribute(forName: "kind")?.stringValue,
            let kind = SvnListEntry.Kind(rawValue: kindRaw),
            let name = entry.elements(forName: "name").first?.stringValue
        else {
            throw SvnKitError.xmlParseFailed("list entry 缺少 kind/name 字段")
        }

        let size = entry.elements(forName: "size").first?.stringValue.flatMap(Int.init)

        var commitRevision: Int?
        var commitAuthor: String?
        var commitDate: Date?
        if let commit = entry.elements(forName: "commit").first {
            commitRevision = commit.attribute(forName: "revision")?.stringValue.flatMap(Int.init)
            commitAuthor = commit.elements(forName: "author").first?.stringValue
            commitDate = commit.elements(forName: "date").first?.stringValue.flatMap(SvnDateParser.parse)
        }

        return SvnListEntry(
            name: name,
            kind: kind,
            size: size,
            commitRevision: commitRevision,
            commitAuthor: commitAuthor,
            commitDate: commitDate
        )
    }
}
