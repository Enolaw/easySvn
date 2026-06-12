import Testing
@testable import SvnKit

@Suite("ConflictMarkerParser")
struct ConflictMarkerParserTests {

    @Test("解析单个冲突块")
    func singleHunk() {
        let text = """
        line1
        <<<<<<< .mine
        my line
        =======
        their line
        >>>>>>> .r5
        line2
        """
        let hunks = ConflictMarkerParser.parse(text)
        #expect(hunks.count == 1)
        #expect(hunks[0].mineText == "my line")
        #expect(hunks[0].theirsText == "their line")
    }

    @Test("采用我的合成结果")
    func mergeMine() {
        let text = """
        <<<<<<< .mine
        A
        =======
        B
        >>>>>>> .r2
        """
        let hunks = ConflictMarkerParser.parse(text)
        let merged = ConflictMarkerParser.mergedText(
            original: text,
            hunks: hunks,
            choices: [0: .mine]
        )
        #expect(merged == "A")
    }
}
