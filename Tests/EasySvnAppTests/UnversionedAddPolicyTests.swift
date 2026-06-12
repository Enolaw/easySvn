import Foundation
import Testing
@testable import EasySvnApp

@Test func unversionedAddPolicyBlocksVenv() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("easysvn-policy-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let venv = root.appendingPathComponent(".venv", isDirectory: true)
    try FileManager.default.createDirectory(at: venv, withIntermediateDirectories: true)

    let evaluation = UnversionedAddPolicy.evaluate(paths: [".venv", "readme.md"], workingCopyRoot: root)
    #expect(evaluation.allowed == ["readme.md"])
    #expect(evaluation.rejected.count == 1)
    #expect(evaluation.rejected.first?.path == ".venv")
}
