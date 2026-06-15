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

@Test func distPathsAreAllowedForTagArchive() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("easysvn-dist-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let dist = root.appendingPathComponent("prod/dist/assets", isDirectory: true)
    try FileManager.default.createDirectory(at: dist, withIntermediateDirectories: true)
    try "console.log()\n".write(to: dist.appendingPathComponent("app.js"), atomically: true, encoding: .utf8)

    let evaluation = UnversionedAddPolicy.evaluate(
        paths: ["prod/dist/assets/app.js", "prod/dist"],
        workingCopyRoot: root
    )
    #expect(evaluation.rejected.isEmpty)
    #expect(evaluation.allowed.count == 2)
}

@Test func rejectedSummaryCollapsesManyPaths() {
    let rejected = (1...500).map { index in
        (path: "project/dist/assets/file\(index).js", reason: "「dist」建议加入 svn:ignore，不宜直接提交")
    }
    let summary = UnversionedAddPolicy.formatRejectedSummary(title: "未执行添加", rejected: rejected)
    #expect(summary.contains("共 500 项被跳过"))
    #expect(summary.contains("500 项"))
    #expect(summary.contains("另有 497 项"))
    #expect(!summary.contains("file500.js"))
}
