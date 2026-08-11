import Foundation
import Testing
@testable import EasySvnApp

@Test func workingCopyRelativePathNormalizesNFDToNFC() {
    let nfc = "软萌奇遇记"
    let nfd = nfc.decomposedStringWithCanonicalMapping
    #expect(nfc != nfd || nfc.count == nfd.count)
    #expect(WorkingCopyRelativePath.normalize(nfd) == WorkingCopyRelativePath.normalize(nfc))
    #expect(WorkingCopyRelativePath.pathsEqual(nfd, nfc))
}

@Test func workingCopyRelativePathDetectsAncestor() {
    #expect(WorkingCopyRelativePath.isSameOrAncestor("project/assets", of: "project/assets/icon.png"))
    #expect(!WorkingCopyRelativePath.isSameOrAncestor("project/other", of: "project/assets/icon.png"))
}
