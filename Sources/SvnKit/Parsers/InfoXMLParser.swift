import Foundation

/// 解析 `svn info --xml` 的输出。
public enum InfoXMLParser {

    public static func parse(_ data: Data) throws -> SvnInfo {
        let document: XMLDocument
        do {
            document = try XMLDocument(data: data)
        } catch {
            throw SvnKitError.xmlParseFailed("info XML 无法解析: \(error.localizedDescription)")
        }

        guard let entry = try document.nodes(forXPath: "/info/entry").first as? XMLElement else {
            throw SvnKitError.xmlParseFailed("info 输出缺少 entry 节点")
        }

        guard
            let kind = entry.attribute(forName: "kind")?.stringValue,
            let revision = entry.attribute(forName: "revision")?.stringValue.flatMap(Int.init),
            let url = entry.elements(forName: "url").first?.stringValue
        else {
            throw SvnKitError.xmlParseFailed("info entry 缺少必要字段")
        }

        guard
            let repository = entry.elements(forName: "repository").first,
            let root = repository.elements(forName: "root").first?.stringValue,
            let uuid = repository.elements(forName: "uuid").first?.stringValue
        else {
            throw SvnKitError.xmlParseFailed("info entry 缺少 repository 信息")
        }

        let relativeURL = entry.elements(forName: "relative-url").first?.stringValue
        let workingCopyRoot = entry.elements(forName: "wc-info").first?
            .elements(forName: "wcroot-abspath").first?.stringValue

        var lastCommitRevision: Int?
        var lastCommitAuthor: String?
        var lastCommitDate: Date?
        if let commit = entry.elements(forName: "commit").first {
            lastCommitRevision = commit.attribute(forName: "revision")?.stringValue.flatMap(Int.init)
            lastCommitAuthor = commit.elements(forName: "author").first?.stringValue
            if let dateString = commit.elements(forName: "date").first?.stringValue {
                lastCommitDate = SvnDateParser.parse(dateString)
            }
        }

        let treeConflict = parseTreeConflict(entry)

        return SvnInfo(
            kind: kind,
            url: url,
            relativeURL: relativeURL,
            repositoryRoot: root,
            repositoryUUID: uuid,
            revision: revision,
            workingCopyRoot: workingCopyRoot,
            lastCommitRevision: lastCommitRevision,
            lastCommitAuthor: lastCommitAuthor,
            lastCommitDate: lastCommitDate,
            treeConflict: treeConflict
        )
    }

    private static func parseTreeConflict(_ entry: XMLElement) -> SvnTreeConflict? {
        guard let node = entry.elements(forName: "tree-conflict").first else {
            return nil
        }
        let operation = node.attribute(forName: "operation")?.stringValue ?? "unknown"
        let urls = node.elements(forName: "urls").first
        let left = urls?.elements(forName: "src-left-side").first?.stringValue
        let right = urls?.elements(forName: "src-right-side").first?.stringValue
        return SvnTreeConflict(operation: operation, sourceLeft: left, sourceRight: right)
    }

}
