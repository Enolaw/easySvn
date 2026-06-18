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
    #expect(evaluation.redirected.isEmpty)
}

@Test func largeVersionFolderRedirectsToProductionDist() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("easysvn-version-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let versionDir = root.appendingPathComponent("project/VUE3/3.11.1", isDirectory: true)
    let distDir = versionDir.appendingPathComponent("production/dist/img", isDirectory: true)
    let srcDir = versionDir.appendingPathComponent("src", isDirectory: true)
    try FileManager.default.createDirectory(at: distDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)

    // 模拟版本目录内大量源码文件（超过 200 个）
    for index in 0..<210 {
        try "src\n".write(
            to: srcDir.appendingPathComponent("file\(index).js"),
            atomically: true,
            encoding: .utf8
        )
    }
    try "img\n".write(to: distDir.appendingPathComponent("icon.png"), atomically: true, encoding: .utf8)

    let evaluation = UnversionedAddPolicy.evaluate(
        paths: ["project/VUE3/3.11.1"],
        workingCopyRoot: root
    )
    #expect(evaluation.rejected.isEmpty)
    #expect(evaluation.allowed == ["project/VUE3/3.11.1/production/dist"])
    #expect(evaluation.redirected.count == 1)
    #expect(evaluation.redirected[0].from == "project/VUE3/3.11.1")
    #expect(evaluation.redirected[0].to == "project/VUE3/3.11.1/production/dist")
}

@Test func largeFolderWithoutDistIsStillRejected() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("easysvn-nodist-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let largeDir = root.appendingPathComponent("big", isDirectory: true)
    try FileManager.default.createDirectory(at: largeDir, withIntermediateDirectories: true)
    for index in 0..<210 {
        try "x\n".write(
            to: largeDir.appendingPathComponent("file\(index).txt"),
            atomically: true,
            encoding: .utf8
        )
    }

    let evaluation = UnversionedAddPolicy.evaluate(paths: ["big"], workingCopyRoot: root)
    #expect(evaluation.allowed.isEmpty)
    #expect(evaluation.redirected.isEmpty)
    #expect(evaluation.rejected.count == 1)
}

@Test func largeVersionFolderRedirectsToProdDist() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("easysvn-prod-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let versionDir = root.appendingPathComponent("project/4.10.1", isDirectory: true)
    let distDir = versionDir.appendingPathComponent("prod/dist/assets", isDirectory: true)
    let srcDir = versionDir.appendingPathComponent("src", isDirectory: true)
    try FileManager.default.createDirectory(at: distDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
    for index in 0..<210 {
        try "src\n".write(to: srcDir.appendingPathComponent("file\(index).js"), atomically: true, encoding: .utf8)
    }
    try "js\n".write(to: distDir.appendingPathComponent("app.js"), atomically: true, encoding: .utf8)

    let evaluation = UnversionedAddPolicy.evaluate(
        paths: ["project/4.10.1"],
        workingCopyRoot: root
    )
    #expect(evaluation.allowed == ["project/4.10.1/prod/dist"])
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
