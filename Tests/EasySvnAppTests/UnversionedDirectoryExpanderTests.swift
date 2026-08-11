import Foundation
import Testing
@testable import EasySvnApp
import SvnKit

@Test func unversionedDirectoryExpanderListsChildren() throws {
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
    let expanded = UnversionedDirectoryExpander.expand(statusEntries, workingCopyRoot: root)

    #expect(expanded.contains { $0.path == "project/4.10.1/production/dist" })
    #expect(expanded.contains { $0.path == "project/4.10.1/production/dist/img/icon.png" })
    #expect(expanded.contains { $0.path == "project/4.10.1/src/main.js" })
}

@Test func unversionedDirectoryExpanderSkipsWhenStatusHasChildren() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("easysvn-expand-skip-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let statusEntries = [
        SvnStatusEntry(path: "project/4.10.1", itemStatus: .unversioned, propsStatus: .none),
        SvnStatusEntry(path: "project/4.10.1/production/dist/app.js", itemStatus: .unversioned, propsStatus: .none)
    ]
    let expanded = UnversionedDirectoryExpander.expand(statusEntries, workingCopyRoot: root)
    #expect(expanded.count == statusEntries.count)
}

@Test func unversionedDirectoryExpanderDoesNotReaddAddedChildren() throws {
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
    let expanded = UnversionedDirectoryExpander.expand(statusEntries, workingCopyRoot: root)
    #expect(expanded.count == 2)
    #expect(expanded.filter { $0.itemStatus == .unversioned }.count == 1)
    #expect(expanded.contains { $0.path == "project/assets/icon.png" && $0.itemStatus == .added })
}
