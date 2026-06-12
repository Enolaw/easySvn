import Foundation
import Testing
@testable import EasySvnApp

@Test func externalDiffArgumentTemplateExpansion() {
    let left = URL(fileURLWithPath: "/tmp/left.txt")
    let right = URL(fileURLWithPath: "/tmp/right.txt")
    let args = ExternalDiffArgumentBuilder.build(
        template: "%left %right --mine %mine --theirs %theirs",
        left: left,
        right: right
    )
    #expect(args == [
        "/tmp/left.txt",
        "/tmp/right.txt",
        "--mine",
        "/tmp/right.txt",
        "--theirs",
        "/tmp/left.txt"
    ])
}
