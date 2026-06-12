import Foundation

/// 从工作副本目录定位 SVN 冲突辅助文件并读取文本。
public enum ConflictFileResolver {

    public static func loadVersions(for relativePath: String, in workingCopy: URL) -> ConflictVersions {
        let fileURL = workingCopy.appendingPathComponent(relativePath)
        let parent = fileURL.deletingLastPathComponent()
        let baseName = fileURL.lastPathComponent
        let working = readText(at: fileURL)

        guard let names = try? FileManager.default.contentsOfDirectory(atPath: parent.path) else {
            return ConflictVersions(working: working)
        }

        var mine: String?
        var revisionFiles: [(revision: Int, path: String)] = []

        for name in names where name.hasPrefix(baseName) {
            let suffix = String(name.dropFirst(baseName.count))
            if suffix == ".mine" {
                mine = readText(at: parent.appendingPathComponent(name))
            } else if suffix.hasPrefix(".r"), let revision = Int(suffix.dropFirst(2)) {
                revisionFiles.append((revision, name))
            } else if suffix.hasPrefix(".merge-left.r"), let revision = Int(suffix.dropFirst(".merge-left.r".count)) {
                revisionFiles.append((revision, name))
            } else if suffix.hasPrefix(".merge-right.r"), let revision = Int(suffix.dropFirst(".merge-right.r".count)) {
                revisionFiles.append((revision, name))
            }
        }

        revisionFiles.sort { $0.revision < $1.revision }

        var base: String?
        var theirs: String?
        if revisionFiles.count >= 2 {
            base = readText(at: parent.appendingPathComponent(revisionFiles[0].path))
            theirs = readText(at: parent.appendingPathComponent(revisionFiles[1].path))
        } else if revisionFiles.count == 1 {
            theirs = readText(at: parent.appendingPathComponent(revisionFiles[0].path))
        }

        return ConflictVersions(mine: mine, base: base, theirs: theirs, working: working)
    }

    public static func writeWorking(_ content: String, for relativePath: String, in workingCopy: URL) throws {
        let fileURL = workingCopy.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private static func readText(at url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
