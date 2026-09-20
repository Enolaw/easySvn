import Foundation
import Testing
@testable import EasySvnApp
import SvnKit

@Test func unversionedDirectoryExpanderListsChildren() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("easysvn-expand-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let versionDir = root.appendingPathComponent("project/4.10.1", isDirectory: true)
    let distDir = versionDir.appendingPathComponent("production/dist/img", isDirectory: true)
    let srcDir = versionDir.appendingPathComponent("src", isDirectory: true)
    try FileManager.default.createDirectory(at: distDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
    try "img\n".write(to: distDir.appendingPathComponent("icon.png"), atomically: true, encoding: .utf8)
    try "src\n".write(to: srcDir.appendingPathComponent("main.js"), atomically: true, encoding: .utf8)

    let statusEntries = [
        SvnStatusEntry(path: "project/4.10.1", itemStatus: .unversioned, propsStatus: .none)
    ]
    let expanded = try await UnversionedDirectoryExpander.expand(statusEntries, workingCopyRoot: root)

    #expect(expanded.contains { $0.path == "project/4.10.1/production/dist" })
    #expect(expanded.contains { $0.path == "project/4.10.1/production/dist/img/icon.png" })
    #expect(expanded.contains { $0.path == "project/4.10.1/src/main.js" })
}

@Test func unversionedDirectoryExpanderSkipsWhenStatusHasChildren() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("easysvn-expand-skip-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let statusEntries = [
        SvnStatusEntry(path: "project/4.10.1", itemStatus: .unversioned, propsStatus: .none),
        SvnStatusEntry(path: "project/4.10.1/production/dist/app.js", itemStatus: .unversioned, propsStatus: .none)
    ]
    let expanded = try await UnversionedDirectoryExpander.expand(statusEntries, workingCopyRoot: root)
    #expect(expanded.count == statusEntries.count)
}

@Test func unversionedDirectoryExpanderPrunesObsoletedParentDirectory() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("easysvn-expand-prune-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let dir = root.appendingPathComponent("project/assets", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try "png\n".write(to: dir.appendingPathComponent("icon.png"), atomically: true, encoding: .utf8)

    let statusEntries = [
        SvnStatusEntry(path: "project/assets", itemStatus: .unversioned, propsStatus: .none),
        SvnStatusEntry(path: "project/assets/icon.png", itemStatus: .added, propsStatus: .none),
    ]
    let pruned = UnversionedDirectoryExpander.pruneObsoletedUnversionedEntries(
        statusEntries,
        workingCopyRoot: root
    )
    #expect(pruned.count == 1)
    #expect(pruned[0].path == "project/assets/icon.png")
    #expect(pruned[0].itemStatus == .added)
}

@Test func unversionedDirectoryExpanderDoesNotReaddAddedChildren() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("easysvn-expand-added-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let dir = root.appendingPathComponent("project/assets", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let fileURL = dir.appendingPathComponent("icon.png")
    try "png\n".write(to: fileURL, atomically: true, encoding: .utf8)

    let statusEntries = [
        SvnStatusEntry(path: "project/assets", itemStatus: .unversioned, propsStatus: .none),
        SvnStatusEntry(path: "project/assets/icon.png", itemStatus: .added, propsStatus: .none),
    ]
    let expanded = try await UnversionedDirectoryExpander.expand(statusEntries, workingCopyRoot: root)
    #expect(expanded.count == 1)
    #expect(expanded.filter { $0.itemStatus == .unversioned }.count == 0)
    #expect(expanded.contains { $0.path == "project/assets/icon.png" && $0.itemStatus == .added })
}

@Test func unversionedDirectoryExpanderUsesNestedSvnStatus() async throws {
    let client = try SvnClient.detect()
    guard let svnadmin = SvnBinaryLocator.locate(named: "svnadmin") else {
        throw TestSetupError(description: "找不到 svnadmin")
    }

    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("easysvn-expand-svn-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let repoURL = tempRoot.appendingPathComponent("repo", isDirectory: true)
    let wcURL = tempRoot.appendingPathComponent("wc", isDirectory: true)
    _ = try await ProcessRunner.run(executable: svnadmin, arguments: ["create", repoURL.path])
    let repo = "file://\(repoURL.path)/trunk"
    _ = try await ProcessRunner.run(
        executable: client.executable,
        arguments: ["mkdir", "-m", "init", repo]
    )
    try await client.checkout(repository: repo, to: wcURL)

    let seriesDir = wcURL.appendingPathComponent("卡面业务/待上架/系列", isDirectory: true)
    try FileManager.default.createDirectory(at: seriesDir, withIntermediateDirectories: true)
    try "png\n".write(to: seriesDir.appendingPathComponent("A款.png"), atomically: true, encoding: .utf8)
    try await client.add(paths: ["卡面业务/待上架/系列/A款.png"], in: wcURL)

    let statusEntries = [
        SvnStatusEntry(path: "卡面业务", itemStatus: .unversioned, propsStatus: .none)
    ]
    let expanded = try await UnversionedDirectoryExpander.expand(
        statusEntries,
        workingCopyRoot: wcURL,
        client: client
    )

    #expect(expanded.contains { $0.itemStatus == .added && $0.path == "卡面业务/待上架/系列/A款.png" })
    #expect(!expanded.contains { $0.path == "卡面业务/待上架/系列/A款.png" && $0.itemStatus == .unversioned })
}

private struct TestSetupError: Error, CustomStringConvertible {
    let description: String
}

@Test func mergePreferringVersionedKeepsAddedOverUnversioned() {
    let entries = [
        SvnStatusEntry(path: "project/a.png", itemStatus: .unversioned, propsStatus: .none),
        SvnStatusEntry(path: "project/a.png", itemStatus: .added, propsStatus: .none),
    ]
    let merged = UnversionedDirectoryExpander.mergePreferringVersioned(entries)
    #expect(merged.count == 1)
    #expect(merged[0].itemStatus == .added)
}
