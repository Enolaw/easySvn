import Foundation
import Testing
@testable import SvnKit

@Suite("StatusXMLParser")
struct StatusXMLParserTests {

    static let fixture = """
    <?xml version="1.0" encoding="UTF-8"?>
    <status>
    <target path=".">
    <entry path="modified.txt">
    <wc-status item="modified" revision="3" props="none">
    <commit revision="2">
    <author>alice</author>
    <date>2026-06-12T02:33:10.123456Z</date>
    </commit>
    </wc-status>
    </entry>
    <entry path="new.txt">
    <wc-status item="unversioned" props="none">
    </wc-status>
    </entry>
    <entry path="conflict.txt">
    <wc-status item="conflicted" revision="3" props="none" tree-conflicted="true">
    </wc-status>
    </entry>
    <entry path="tools">
    <wc-status item="normal" revision="3" props="modified">
    </wc-status>
    </entry>
    </target>
    </status>
    """

    @Test("解析多种状态条目")
    func parseEntries() throws {
        let entries = try StatusXMLParser.parse(Data(Self.fixture.utf8))
        #expect(entries.count == 4)

        let modified = try #require(entries.first { $0.path == "modified.txt" })
        #expect(modified.itemStatus == .modified)
        #expect(modified.revision == 3)
        #expect(modified.commitRevision == 2)
        #expect(modified.commitAuthor == "alice")
        #expect(!modified.isTreeConflicted)

        let unversioned = try #require(entries.first { $0.path == "new.txt" })
        #expect(unversioned.itemStatus == .unversioned)
        #expect(unversioned.revision == nil)

        let conflicted = try #require(entries.first { $0.path == "conflict.txt" })
        #expect(conflicted.itemStatus == .conflicted)
        #expect(conflicted.isTreeConflicted)

        let propsOnly = try #require(entries.first { $0.path == "tools" })
        #expect(propsOnly.itemStatus == .normal)
        #expect(propsOnly.propsStatus == .modified)
        #expect(propsOnly.isPropsOnlyModified)
        #expect(propsOnly.isCommittable)
        #expect(propsOnly.displayStatus == .modified)
    }

    @Test("空 status 输出")
    func parseEmpty() throws {
        let xml = #"<?xml version="1.0"?><status><target path="."></target></status>"#
        let entries = try StatusXMLParser.parse(Data(xml.utf8))
        #expect(entries.isEmpty)
    }

    @Test("非法 XML 抛错")
    func invalidXML() {
        #expect(throws: SvnKitError.self) {
            _ = try StatusXMLParser.parse(Data("not xml".utf8))
        }
    }
}

@Suite("InfoXMLParser")
struct InfoXMLParserTests {

    static let fixture = """
    <?xml version="1.0" encoding="UTF-8"?>
    <info>
    <entry kind="dir" path="." revision="5">
    <url>file:///tmp/repo/trunk</url>
    <relative-url>^/trunk</relative-url>
    <repository>
    <root>file:///tmp/repo</root>
    <uuid>6e0a3c40-7a3b-4f1e-9c2d-000000000000</uuid>
    </repository>
    <wc-info>
    <wcroot-abspath>/Users/test/wc</wcroot-abspath>
    <schedule>normal</schedule>
    <depth>infinity</depth>
    </wc-info>
    <commit revision="5">
    <author>bob</author>
    <date>2026-06-12T02:33:10.123456Z</date>
    </commit>
    </entry>
    </info>
    """

    @Test("解析 info 输出")
    func parseInfo() throws {
        let info = try InfoXMLParser.parse(Data(Self.fixture.utf8))
        #expect(info.kind == "dir")
        #expect(info.revision == 5)
        #expect(info.url == "file:///tmp/repo/trunk")
        #expect(info.relativeURL == "^/trunk")
        #expect(info.repositoryRoot == "file:///tmp/repo")
        #expect(info.workingCopyRoot == "/Users/test/wc")
        #expect(info.lastCommitRevision == 5)
        #expect(info.lastCommitAuthor == "bob")
        #expect(info.lastCommitDate != nil)
    }

    @Test("日期解析支持小数秒")
    func parseDate() {
        #expect(SvnDateParser.parse("2026-06-12T02:33:10.123456Z") != nil)
        #expect(SvnDateParser.parse("2026-06-12T02:33:10Z") != nil)
        #expect(SvnDateParser.parse("bogus") == nil)
    }
}

@Suite("LogXMLParser")
struct LogXMLParserTests {

    static let fixture = """
    <?xml version="1.0" encoding="UTF-8"?>
    <log>
    <logentry revision="2">
    <author>alice</author>
    <date>2026-06-12T02:33:10.123456Z</date>
    <paths>
    <path action="M" kind="file">/trunk/foo.txt</path>
    <path action="A" kind="file" copyfrom-path="/trunk/old.txt" copyfrom-rev="1">/trunk/new.txt</path>
    </paths>
    <msg>fix bug</msg>
    </logentry>
    <logentry revision="1">
    <author>bob</author>
    <date>2026-06-11T08:00:00.000000Z</date>
    <msg></msg>
    </logentry>
    </log>
    """

    @Test("解析 verbose 日志")
    func parseVerboseLog() throws {
        let entries = try LogXMLParser.parse(Data(Self.fixture.utf8))
        #expect(entries.count == 2)

        let latest = entries[0]
        #expect(latest.revision == 2)
        #expect(latest.author == "alice")
        #expect(latest.message == "fix bug")
        #expect(latest.date != nil)
        #expect(latest.changedPaths.count == 2)

        let modified = try #require(latest.changedPaths.first { $0.path == "/trunk/foo.txt" })
        #expect(modified.action == .modified)
        #expect(modified.kind == "file")

        let copied = try #require(latest.changedPaths.first { $0.path == "/trunk/new.txt" })
        #expect(copied.action == .added)
        #expect(copied.copyFromPath == "/trunk/old.txt")
        #expect(copied.copyFromRevision == 1)

        // 无 paths 节点、空 msg 的条目
        #expect(entries[1].revision == 1)
        #expect(entries[1].changedPaths.isEmpty)
        #expect(entries[1].message.isEmpty)
    }
}

@Suite("ListXMLParser")
struct ListXMLParserTests {

    static let fixture = """
    <?xml version="1.0" encoding="UTF-8"?>
    <lists>
    <list path="file:///tmp/repo">
    <entry kind="dir">
    <name>trunk</name>
    <commit revision="3"><author>alice</author><date>2026-06-12T02:33:10.123456Z</date></commit>
    </entry>
    <entry kind="file">
    <name>readme.txt</name>
    <size>42</size>
    <commit revision="1"><author>bob</author><date>2026-06-11T08:00:00.000000Z</date></commit>
    </entry>
    </list>
    </lists>
    """

    @Test("解析目录与文件条目")
    func parseEntries() throws {
        let entries = try ListXMLParser.parse(Data(Self.fixture.utf8))
        #expect(entries.count == 2)

        let dir = try #require(entries.first { $0.name == "trunk" })
        #expect(dir.kind == .dir)
        #expect(dir.size == nil)
        #expect(dir.commitRevision == 3)

        let file = try #require(entries.first { $0.name == "readme.txt" })
        #expect(file.kind == .file)
        #expect(file.size == 42)
        #expect(file.commitAuthor == "bob")
    }
}

@Suite("SvnError")
struct SvnErrorTests {

    @Test("从 stderr 提取错误码")
    func parseErrorCode() {
        let stderr = "svn: E155007: '/tmp/foo' is not a working copy\n"
        let result = ProcessResult(
            exitCode: 1,
            standardOutput: Data(),
            standardError: Data(stderr.utf8)
        )
        let error = SvnError.parse(from: result)
        #expect(error.code == SvnError.Code.notAWorkingCopy)
        #expect(error.exitCode == 1)
        #expect(error.message.contains("not a working copy"))
    }

    @Test("无错误码时 code 为 nil")
    func parseWithoutCode() {
        let result = ProcessResult(
            exitCode: 2,
            standardOutput: Data(),
            standardError: Data("something went wrong".utf8)
        )
        let error = SvnError.parse(from: result)
        #expect(error.code == nil)
        #expect(error.message == "something went wrong")
    }
}
