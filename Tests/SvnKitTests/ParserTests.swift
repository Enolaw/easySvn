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
    </target>
    </status>
    """

    @Test("解析多种状态条目")
    func parseEntries() throws {
        let entries = try StatusXMLParser.parse(Data(Self.fixture.utf8))
        #expect(entries.count == 3)

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
        #expect(InfoXMLParser.parseDate("2026-06-12T02:33:10.123456Z") != nil)
        #expect(InfoXMLParser.parseDate("2026-06-12T02:33:10Z") != nil)
        #expect(InfoXMLParser.parseDate("bogus") == nil)
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
