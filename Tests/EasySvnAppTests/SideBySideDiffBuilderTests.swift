import Foundation
import Testing
@testable import EasySvnApp

@Test func sideBySideDiffAlignsChanges() {
    let diff = """
    --- a/file.txt
    +++ b/file.txt
    @@ -1,3 +1,4 @@
     line1
    -line2
    +line2b
     line3
    +line4
    """
    let lines = UnifiedDiffParser.parse(diff)
    let rows = SideBySideDiffBuilder.build(from: lines)

    #expect(rows.contains { $0.leftText == "line1" && $0.rightText == "line1" })
    #expect(rows.contains { $0.leftText == "line2" && $0.rightText == "line2b" })
    #expect(rows.contains { $0.leftText == "line3" && $0.rightText == "line3" })
    #expect(rows.contains { $0.leftText == nil && $0.rightText == "line4" })
}

@Test func sideBySideDiffMarksHunkHeaders() {
    let diff = """
    @@ -10,2 +10,2 @@
     keep
    -old
    +new
    """
    let rows = SideBySideDiffBuilder.build(from: UnifiedDiffParser.parse(diff))
    #expect(rows.first?.isHunkHeader == true)
    #expect(rows.first?.hunkLabel == "旧版本第 10 行 · 新版本第 10 行")
}

@Test func sideBySideDiffAddsInlineHighlightOnPairedLines() {
    let diff = """
    @@ -1,1 +1,1 @@
    -title = 旧标题
    +title = 新标题
    """
    let rows = SideBySideDiffBuilder.build(from: UnifiedDiffParser.parse(diff))
    let changed = rows.first { $0.leftHighlight == .deletion && $0.rightHighlight == .addition }
    #expect(changed != nil)
    #expect(changed?.leftInlineRanges.isEmpty == false)
    #expect(changed?.rightInlineRanges.isEmpty == false)
}

@Test func sideBySideDiffChangeBlocksGroupConsecutiveEdits() {
    let diff = """
    @@ -1,5 +1,5 @@
     a
    -b
    +b2
     c
    -d
    +d2
     e
    """
    let rows = SideBySideDiffBuilder.build(from: UnifiedDiffParser.parse(diff))
    let blocks = SideBySideDiffBuilder.changeBlockIDs(in: rows)
    #expect(blocks.count == 2)
}

@Test func fullTextDiffAlignsInsertedLineWithoutShiftingRest() {
    let left = """
    alpha
    beta
    gamma
    """
    let right = """
    intro
    alpha
    beta
    gamma
    """
    let rows = SideBySideDiffBuilder.buildFromFullText(left: left, right: right)
    #expect(rows.contains { $0.leftText == nil && $0.rightText == "intro" })
    #expect(rows.contains { $0.leftText == "alpha" && $0.rightText == "alpha" && $0.leftHighlight == .context })
    #expect(rows.contains { $0.leftText == "gamma" && $0.rightText == "gamma" && $0.leftHighlight == .context })
}

@Test func imageFileDetectorRecognizesCommonFormats() {
    #expect(ImageFileDetector.isImage("assets/icon.PNG"))
    #expect(ImageFileDetector.isImage("photo.jpeg"))
    #expect(!ImageFileDetector.isImage("readme.md"))
}

@Test func unifiedParserReportsChangeBlocks() {
    let diff = """
    --- a/file.txt
    +++ b/file.txt
    @@ -1,3 +1,3 @@
     keep
    -old
    +new
     tail
    """
    let lines = UnifiedDiffParser.parse(diff)
    let blocks = UnifiedDiffParser.changeBlockIDs(in: lines)
    #expect(blocks.count == 1)
}

@Test func unifiedParserSplitsCRSeparatedHunkBody() {
    let diff = "@@ -183,3 +183,3 @@\n jumpToProductDetailByGoodsId,\r-    LocalStorageKey,\r+    supportRandomChange,\r getMallImageUrl,"
    let lines = UnifiedDiffParser.parse(diff)
    let rows = SideBySideDiffBuilder.build(from: lines)

    #expect(lines.contains { $0.kind == .deletion && $0.text.contains("LocalStorageKey") })
    #expect(lines.contains { $0.kind == .addition && $0.text.contains("supportRandomChange") })
    #expect(rows.contains { $0.leftHighlight == .deletion && $0.leftText?.contains("LocalStorageKey") == true })
    #expect(rows.contains { $0.rightHighlight == .addition && $0.rightText?.contains("supportRandomChange") == true })
    #expect(!SideBySideDiffBuilder.changeBlockIDs(in: rows).isEmpty)
}

@Test func fullTextDiffIgnoresCRLFVersusLF() {
    let rows = SideBySideDiffBuilder.buildFromFullText(
        left: "alpha\r\nbeta\r\n",
        right: "alpha\nbeta\n"
    )
    #expect(rows.allSatisfy { $0.leftHighlight == .context && $0.rightHighlight == .context || $0.leftText == "" || $0.rightText == "" })
    #expect(!rows.contains { $0.leftHighlight == .deletion || $0.rightHighlight == .addition })
}
