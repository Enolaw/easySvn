import Foundation

/// 行内高亮区间（按 Character 偏移，而非 UTF-16）。
struct InlineHighlightRange: Equatable, Sendable {
    let start: Int
    let length: Int
}

/// 计算配对行内真正改动的区间：英文按词、中日韩按字。
enum InlineDiffHighlighter {

    /// 变更占比过高时不做行内高亮，避免整行涂满。
    static let maxChangeRatio = 0.72
    static let maxCharacterCount = 4_000

    static func changedRanges(
        left: String,
        right: String
    ) -> (left: [InlineHighlightRange], right: [InlineHighlightRange]) {
        if left == right || left.isEmpty || right.isEmpty {
            return ([], [])
        }

        let leftCount = left.count
        let rightCount = right.count
        if leftCount > maxCharacterCount || rightCount > maxCharacterCount {
            return ([], [])
        }

        let leftTokens = tokenize(left)
        let rightTokens = tokenize(right)
        var leftOffsets: [Int] = []
        var rightOffsets: [Int] = []

        for change in rightTokens.map(\.text).difference(from: leftTokens.map(\.text)) {
            switch change {
            case .remove(let offset, _, _):
                let token = leftTokens[offset]
                leftOffsets.append(contentsOf: token.start..<(token.start + token.length))
            case .insert(let offset, _, _):
                let token = rightTokens[offset]
                rightOffsets.append(contentsOf: token.start..<(token.start + token.length))
            }
        }

        let changed = leftOffsets.count + rightOffsets.count
        let total = max(leftCount + rightCount, 1)
        if Double(changed) / Double(total) > maxChangeRatio {
            return ([], [])
        }

        return (merge(leftOffsets), merge(rightOffsets))
    }

    static func characterRange(in text: String, start: Int, length: Int) -> Range<String.Index>? {
        guard start >= 0, length > 0 else { return nil }
        var index = text.startIndex
        var offset = 0
        var rangeStart: String.Index?
        while index < text.endIndex {
            if offset == start {
                rangeStart = index
            }
            if offset == start + length {
                if let rangeStart {
                    return rangeStart..<index
                }
                return nil
            }
            index = text.index(after: index)
            offset += 1
        }
        if let rangeStart, offset > start {
            return rangeStart..<text.endIndex
        }
        return nil
    }

    private struct Token {
        let text: String
        let start: Int
        var length: Int { text.count }
    }

    private static func tokenize(_ text: String) -> [Token] {
        let chars = Array(text)
        var tokens: [Token] = []
        var index = 0
        while index < chars.count {
            let start = index
            let character = chars[index]
            if isCJK(character) {
                index += 1
            } else if isWordCharacter(character) {
                while index < chars.count,
                      isWordCharacter(chars[index]),
                      !isCJK(chars[index]) {
                    index += 1
                }
            } else if character.isWhitespace {
                while index < chars.count, chars[index].isWhitespace {
                    index += 1
                }
            } else {
                index += 1
            }
            tokens.append(Token(text: String(chars[start..<index]), start: start))
        }
        return tokens
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character == "_" || character.isLetter || character.isNumber
    }

    private static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            let value = scalar.value
            switch value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF,
                 0x3040...0x30FF, 0xAC00...0xD7AF, 0x20000...0x2CEAF:
                return true
            default:
                return false
            }
        }
    }

    private static func merge(_ offsets: [Int]) -> [InlineHighlightRange] {
        let sorted = offsets.sorted()
        guard let first = sorted.first else { return [] }

        var ranges: [InlineHighlightRange] = []
        var start = first
        var end = first
        for offset in sorted.dropFirst() {
            if offset == end + 1 {
                end = offset
            } else {
                ranges.append(InlineHighlightRange(start: start, length: end - start + 1))
                start = offset
                end = offset
            }
        }
        ranges.append(InlineHighlightRange(start: start, length: end - start + 1))
        return ranges
    }
}
