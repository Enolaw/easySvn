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
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(kindFolderURL(repositoryRoot: repositoryRoot, kind: kind))/\(trimmed)"
    }
}
