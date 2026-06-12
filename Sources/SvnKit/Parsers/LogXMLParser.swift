import Foundation

/// 解析 `svn log --xml [--verbose]` 的输出。
///
/// 输出结构示例：
/// ```xml
/// <log>
///   <logentry revision="2">
///     <author>alice</author>
///     <date>2026-06-12T02:33:10.123456Z</date>
///     <paths>
///       <path action="M" kind="file">/trunk/foo.txt</path>
///     </paths>
///     <msg>fix bug</msg>
///   </logentry>
/// </log>
/// ```
public enum LogXMLParser {

    public static func parse(_ data: Data) throws -> [SvnLogEntry] {
        let document: XMLDocument
        do {
            document = try XMLDocument(data: data)
        } catch {
            throw SvnKitError.xmlParseFailed("log XML 无法解析: \(error.localizedDescription)")
        }

        let entryNodes = try document.nodes(forXPath: "/log/logentry")
        return try entryNodes.compactMap { $0 as? XMLElement }.map(parseEntry(_:))
    }

    private static func parseEntry(_ entry: XMLElement) throws -> SvnLogEntry {
        guard let revision = entry.attribute(forName: "revision")?.stringValue.flatMap(Int.init) else {
            throw SvnKitError.xmlParseFailed("logentry 缺少 revision 属性")
        }

        let author = entry.elements(forName: "author").first?.stringValue
        let date = entry.elements(forName: "date").first?.stringValue.flatMap(SvnDateParser.parse)
        let message = entry.elements(forName: "msg").first?.stringValue ?? ""

        var changedPaths: [SvnChangedPath] = []
        if let paths = entry.elements(forName: "paths").first {
            changedPaths = paths.elements(forName: "path").compactMap(parseChangedPath(_:))
        }

        return SvnLogEntry(
            revision: revision,
            author: author,
            date: date,
            message: message,
            changedPaths: changedPaths
        )
    }

    private static func parseChangedPath(_ element: XMLElement) -> SvnChangedPath? {
        guard
            let actionRaw = element.attribute(forName: "action")?.stringValue,
            let action = SvnChangeAction(rawValue: actionRaw),
            let path = element.stringValue
        else {
            return nil
        }
        return SvnChangedPath(
            action: action,
            path: path,
            kind: element.attribute(forName: "kind")?.stringValue,
            copyFromPath: element.attribute(forName: "copyfrom-path")?.stringValue,
            copyFromRevision: element.attribute(forName: "copyfrom-rev")?.stringValue.flatMap(Int.init)
        )
    }
}
