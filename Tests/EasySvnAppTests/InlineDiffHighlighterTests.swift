import Foundation
import Testing
@testable import EasySvnApp

@Test func inlineDiffHighlightsChangedWords() {
    let pair = InlineDiffHighlighter.changedRanges(left: "hello world", right: "hello there")
    #expect(!pair.left.isEmpty)
    #expect(!pair.right.isEmpty)

    let leftCovered = coveredText("hello world", ranges: pair.left)
    let rightCovered = coveredText("hello there", ranges: pair.right)
    #expect(leftCovered.contains("world"))
    #expect(rightCovered.contains("there"))
    #expect(!leftCovered.contains("hello"))
    #expect(!rightCovered.contains("hello"))
}

@Test func inlineDiffSkipsNearlyRewrittenLines() {
    let pair = InlineDiffHighlighter.changedRanges(left: "abc", right: "xyz")
    #expect(pair.left.isEmpty)
    #expect(pair.right.isEmpty)
}

@Test func inlineDiffSkipsIdenticalOrEmptyLines() {
    #expect(InlineDiffHighlighter.changedRanges(left: "same", right: "same").left.isEmpty)
    #expect(InlineDiffHighlighter.changedRanges(left: "", right: "added").left.isEmpty)
    #expect(InlineDiffHighlighter.changedRanges(left: "gone", right: "").right.isEmpty)
}

@Test func inlineDiffHighlightsChineseCharacters() {
    let pair = InlineDiffHighlighter.changedRanges(left: "欢迎使用旧标题", right: "欢迎使用新标题")
    let leftCovered = coveredText("欢迎使用旧标题", ranges: pair.left)
    let rightCovered = coveredText("欢迎使用新标题", ranges: pair.right)
    #expect(leftCovered.contains("旧"))
    #expect(rightCovered.contains("新"))
    #expect(!leftCovered.contains("欢迎"))
}

@Test func characterRangeMapsCharacterOffsets() {
    let text = "欢迎abc"
    let range = InlineDiffHighlighter.characterRange(in: text, start: 2, length: 3)
    #expect(range != nil)
    #expect(String(text[range!]) == "abc")
}

private func coveredText(_ text: String, ranges: [InlineHighlightRange]) -> String {
    let chars = Array(text)
    return ranges.map { range in
        let from = range.start
        let to = min(range.start + range.length, chars.count)
        return String(chars[from..<to])
    }.joined()
}
