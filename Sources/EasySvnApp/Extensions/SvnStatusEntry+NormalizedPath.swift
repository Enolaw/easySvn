import Foundation
import SvnKit

extension SvnStatusEntry {

    func withNormalizedPath() -> SvnStatusEntry {
        SvnStatusEntry(
            path: WorkingCopyRelativePath.normalize(path),
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
}
