import Foundation

/// 分支/标签类型。
public enum RepositoryCopyKind: String, Sendable, CaseIterable, Identifiable {
    case branch
    case tag

    public var id: String { rawValue }

    public var folderName: String {
        switch self {
        case .branch: "branches"
        case .tag: "tags"
        }
    }

    public var displayName: String {
        switch self {
        case .branch: "分支"
        case .tag: "标签"
        }
    }
}

/// 根据仓库根 URL 构造分支/标签目标路径。
public enum RepositoryURLBuilder {

    public static func normalizedRoot(_ repositoryRoot: String) -> String {
        repositoryRoot.hasSuffix("/") ? String(repositoryRoot.dropLast()) : repositoryRoot
    }

    /// `branches` / `tags` 目录 URL。
    public static func kindFolderURL(repositoryRoot: String, kind: RepositoryCopyKind) -> String {
        "\(normalizedRoot(repositoryRoot))/\(kind.folderName)"
    }

    public static func destinationURL(
        repositoryRoot: String,
        kind: RepositoryCopyKind,
        name: String
    ) -> String {
        let trimmed = sanitizeCopyName(name)
        guard !trimmed.isEmpty else { return "" }
        return "\(kindFolderURL(repositoryRoot: repositoryRoot, kind: kind))/\(trimmed)"
    }

    /// 规范化分支/标签名称（误粘贴 URL 时取最后一段路径）。
    public static func sanitizeCopyName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if trimmed.contains("://") {
            return RepositoryURLHelper.lastComponent(of: trimmed)
        }
        if trimmed.contains("/") {
            return (trimmed as NSString).lastPathComponent
        }
        return trimmed
    }

    /// 根据来源 URL 推断目标路径（兼容 `XX_SourceCodes/03_Tag/` 等企业仓库布局）。
    public static func inferredDestinationURL(
        sourceURL: String,
        repositoryRoot: String,
        kind: RepositoryCopyKind,
        name: String
    ) -> String {
        let sanitized = sanitizeCopyName(name)
        guard !sanitized.isEmpty else { return "" }
        if let custom = enterpriseLayoutDestination(sourceURL: sourceURL, kind: kind, name: sanitized) {
            return custom
        }
        return destinationURL(repositoryRoot: repositoryRoot, kind: kind, name: sanitized)
    }

    /// 解析最终 copy 目标；目标 URL 仅为 Tag 目录时自动追加版本号。
    public static func resolvedCopyDestination(baseURL: String, name: String) -> String {
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitized = sanitizeCopyName(name)
        guard !trimmedBase.isEmpty, !sanitized.isEmpty else { return trimmedBase }
        if trimmedBase.hasSuffix("/\(sanitized)") {
            return trimmedBase
        }
        if RepositoryURLHelper.lastComponent(of: trimmedBase) == sanitized {
            return trimmedBase
        }
        return RepositoryURLHelper.childURL(parent: trimmedBase, name: sanitized)
    }

    private static let sourceCodesMarker = "_SourceCodes/"
    private static let tagFolderName = "03_Tag"

    private static func enterpriseLayoutDestination(
        sourceURL: String,
        kind: RepositoryCopyKind,
        name: String
    ) -> String? {
        switch kind {
        case .tag:
            return tagDestinationFromSourceCodesLayout(sourceURL: sourceURL, name: name)
        case .branch:
            return nil
        }
    }

    /// `.../05_SourceCodes/...` → `.../05_SourceCodes/03_Tag/{project}/{name}`
    private static func tagDestinationFromSourceCodesLayout(sourceURL: String, name: String) -> String? {
        guard let markerRange = sourceURL.range(of: sourceCodesMarker) else { return nil }
        let prefix = String(sourceURL[..<markerRange.upperBound]) + "\(tagFolderName)/"
        var remainder = String(sourceURL[markerRange.upperBound...])
        if remainder.hasPrefix("\(tagFolderName)/") {
            remainder = String(remainder.dropFirst("\(tagFolderName)/".count))
        }
        let parts = remainder.split(separator: "/").map(String.init)
        guard !parts.isEmpty else { return prefix + name }
        let projectPath = parts.count >= 2 ? parts.dropLast().joined(separator: "/") : parts[0]
        if projectPath.isEmpty {
            return prefix + name
        }
        return "\(prefix)\(projectPath)/\(name)"
    }
}
