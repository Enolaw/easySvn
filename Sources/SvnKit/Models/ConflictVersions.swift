import Foundation

/// 冲突文件的三方文本内容（mine / base / theirs）及带标记的工作副本。
public struct ConflictVersions: Sendable, Equatable {
    public let mine: String?
    public let base: String?
    public let theirs: String?
    public let working: String?

    public var hasTextConflict: Bool {
        mine != nil || base != nil || theirs != nil || working?.contains("<<<<<<<") == true
    }

    public init(
        mine: String? = nil,
        base: String? = nil,
        theirs: String? = nil,
        working: String? = nil
    ) {
        self.mine = mine
        self.base = base
        self.theirs = theirs
        self.working = working
    }
}
