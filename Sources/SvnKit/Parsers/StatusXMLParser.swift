import Foundation

/// 解析 `svn status --xml` 的输出。
///
/// 输出结构示例：
/// ```xml
/// <status>
///   <target path=".">
///     <entry path="foo.txt">
///       <wc-status item="modified" props="none" revision="3">
///         <commit revision="2"><author>alice</author><date>...</date></commit>
///       </wc-status>
///     </entry>
///   </target>
/// </status>
/// ```
public enum StatusXMLParser {

    public static func parse(_ data: Data) throws -> [SvnStatusEntry] {
        let document: XMLDocument
        do {
            document = try XMLDocument(data: data)
        } catch {
            throw SvnKitError.xmlParseFailed("status XML 无法解析: \(error.localizedDescription)")
        }

        let entryNodes = try document.nodes(forXPath: "/status/target/entry")
        return try entryNodes.compactMap { $0 as? XMLElement }.map(parseEntry(_:))
    }

    private static func parseEntry(_ entry: XMLElement) throws -> SvnStatusEntry {
        guard let path = entry.attribute(forName: "path")?.stringValue else {
            throw SvnKitError.xmlParseFailed("status entry 缺少 path 属性")
        }
        guard let wcStatus = entry.elements(forName: "wc-status").first else {
            throw SvnKitError.xmlParseFailed("status entry 缺少 wc-status 节点: \(path)")
        }

        let itemStatus = status(from: wcStatus.attribute(forName: "item")?.stringValue)
        let propsStatus = status(from: wcStatus.attribute(forName: "props")?.stringValue)
        let revision = wcStatus.attribute(forName: "revision")?.stringValue.flatMap(Int.init)
        let isTreeConflicted = boolAttribute(wcStatus, "tree-conflicted")
        let isCopied = boolAttribute(wcStatus, "copied")
        let isWCLocked = boolAttribute(wcStatus, "wc-locked")

        var commitRevision: Int?
        var commitAuthor: String?
        if let commit = wcStatus.elements(forName: "commit").first {
            commitRevision = commit.attribute(forName: "revision")?.stringValue.flatMap(Int.init)
            commitAuthor = commit.elements(forName: "author").first?.stringValue
        }

        return SvnStatusEntry(
            path: path,
            itemStatus: itemStatus,
            propsStatus: propsStatus,
            revision: revision,
            commitRevision: commitRevision,
            commitAuthor: commitAuthor,
            isTreeConflicted: isTreeConflicted,
            isCopied: isCopied,
            isWCLocked: isWCLocked
        )
    }

    private static func status(from raw: String?) -> SvnItemStatus {
        guard let raw else { return .none }
        return SvnItemStatus(rawValue: raw) ?? .none
    }

    private static func boolAttribute(_ element: XMLElement, _ name: String) -> Bool {
        element.attribute(forName: name)?.stringValue == "true"
    }
}
