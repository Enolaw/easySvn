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

@Test func imageFileDetectorRecognizesCommonFormats() {
    #expect(ImageFileDetector.isImage("assets/icon.PNG"))
    #expect(ImageFileDetector.isImage("photo.jpeg"))
    #expect(!ImageFileDetector.isImage("readme.md"))
}
