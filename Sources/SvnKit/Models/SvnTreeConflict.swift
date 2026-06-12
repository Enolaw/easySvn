import Foundation

/// `svn info --xml` 中的树冲突信息。
public struct SvnTreeConflict: Sendable, Equatable {
    public let operation: String
    public let sourceLeft: String?
    public let sourceRight: String?

    public init(operation: String, sourceLeft: String? = nil, sourceRight: String? = nil) {
        self.operation = operation
        self.sourceLeft = sourceLeft
        self.sourceRight = sourceRight
    }
}
