import Foundation

/// `svn info` 的结果。
public struct SvnInfo: Sendable, Equatable {
    public let kind: String
    public let url: String
    public let relativeURL: String?
    public let repositoryRoot: String
    public let repositoryUUID: String
    public let revision: Int
    /// 工作副本根目录（对远程 URL 执行 info 时为 nil）。
    public let workingCopyRoot: String?
    public let lastCommitRevision: Int?
    public let lastCommitAuthor: String?
    public let lastCommitDate: Date?

    public init(
        kind: String,
        url: String,
        relativeURL: String? = nil,
        repositoryRoot: String,
        repositoryUUID: String,
        revision: Int,
        workingCopyRoot: String? = nil,
        lastCommitRevision: Int? = nil,
        lastCommitAuthor: String? = nil,
        lastCommitDate: Date? = nil
    ) {
        self.kind = kind
        self.url = url
        self.relativeURL = relativeURL
        self.repositoryRoot = repositoryRoot
        self.repositoryUUID = repositoryUUID
        self.revision = revision
        self.workingCopyRoot = workingCopyRoot
        self.lastCommitRevision = lastCommitRevision
        self.lastCommitAuthor = lastCommitAuthor
        self.lastCommitDate = lastCommitDate
    }
}
