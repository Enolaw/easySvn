import Foundation
import Testing
@testable import EasySvnApp

@Test func nestedWorkingCopyDetectorFindsNestedSvnDirectory() throws {
    let outer = FileManager.default.temporaryDirectory
        .appendingPathComponent("easysvn-nested-detect-\(UUID().uuidString)", isDirectory: true)
    let inner = outer.appendingPathComponent("卡面业务/待上架/云朵耶小兔", isDirectory: true)
    try FileManager.default.createDirectory(
        at: inner.appendingPathComponent(".svn", isDirectory: true),
        withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
        at: outer.appendingPathComponent(".svn", isDirectory: true),
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: outer) }

    let nested = NestedWorkingCopyDetector.detect(in: outer)
    #expect(nested.count == 1)
    #expect(nested[0].relativePath == "卡面业务/待上架/云朵耶小兔")
}

@Test func nestedWorkingCopyDetectorFiltersDescendantEntries() {
    let entries = [
        "卡面业务/待上架/云朵耶小兔",
        "卡面业务/待上架/云朵耶小兔/软萌奇遇记系列/a.png",
        "卡面交接/宝可梦/a.csv",
    ]
    let filtered = NestedWorkingCopyDetector.filterEntries(
        entries,
        path: { $0 },
        nestedRoots: ["卡面业务/待上架/云朵耶小兔"]
    )
    #expect(filtered == [
        "卡面业务/待上架/云朵耶小兔",
        "卡面交接/宝可梦/a.csv",
    ])
}

@Test func nestedWorkingCopyDetectorDirectoryURL() {
    let outer = URL(fileURLWithPath: "/tmp/outer", isDirectory: true)
    let nested = NestedWorkingCopy(relativePath: "project/nested")
    #expect(nested.directoryURL(in: outer).path.hasSuffix("/tmp/outer/project/nested"))
}

@Test func nestedWorkingCopyDetectorRemovesMetadata() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("easysvn-nested-remove-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let svnURL = directory.appendingPathComponent(".svn", isDirectory: true)
    try FileManager.default.createDirectory(at: svnURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    try NestedWorkingCopyDetector.removeMetadata(at: directory)
    #expect(!FileManager.default.fileExists(atPath: svnURL.path))
}
