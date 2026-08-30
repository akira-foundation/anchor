import Foundation
import Testing

@testable import AnchorProvider

@Suite("Abridging what a tool produced")
struct ToolOutputTests {
    private func longOutput(lines: Int) -> String {
        (1...lines).map { "line \($0) of build output" }.joined(separator: "\n")
    }

    @Test("an output that fits is left exactly as it was")
    func anOutputThatFitsIsLeftExactlyAsItWas() {
        let output = "all tests passed"

        #expect(ToolOutput.abridged(output) == output)
    }

    @Test("an output at the limit is still left alone")
    func anOutputAtTheLimitIsStillLeftAlone() {
        let output = String(repeating: "a", count: ToolOutput.maximumByteCount)

        #expect(ToolOutput.abridged(output) == output)
    }

    @Test("a long output keeps its beginning and its end")
    func aLongOutputKeepsItsBeginningAndItsEnd() {
        let output = "FIRST\n" + longOutput(lines: 2000) + "\nerror: build failed"

        let abridged = ToolOutput.abridged(output)

        #expect(abridged.hasPrefix("FIRST\n"))
        #expect(abridged.hasSuffix("error: build failed"))
        #expect(abridged.utf8.count < output.utf8.count)
    }

    @Test("the mark says how much disappeared")
    func theMarkSaysHowMuchDisappeared() {
        let output = longOutput(lines: 2000)

        let abridged = ToolOutput.abridged(output)

        #expect(abridged.contains("[omitted "))
        #expect(abridged.contains(" bytes of 1999 lines]"))
    }

    @Test("abridging what was already abridged changes nothing")
    func abridgingWhatWasAlreadyAbridgedChangesNothing() {
        let once = ToolOutput.abridged(longOutput(lines: 2000))

        #expect(ToolOutput.abridged(once) == once)
    }

    @Test("an image becomes a description of itself")
    func anImageBecomesADescriptionOfItself() {
        let block: [[String: Any]] = [
            [
                "type": "image",
                "source": [
                    "type": "base64", "media_type": "image/png",
                    "data": String(repeating: "iVBORw0KGgo", count: 100),
                ],
            ]
        ]

        let rendered = ToolOutput.summarised(block)

        #expect(rendered == "[image omitted: image/png, 1100 encoded bytes]")
    }

    @Test("text around an image survives the image being dropped")
    func textAroundAnImageSurvivesTheImageBeingDropped() {
        let blocks: [[String: Any]] = [
            ["type": "text", "text": "tapped the button"],
            ["type": "image", "source": ["media_type": "image/jpeg", "data": "abcd"]],
            ["type": "text", "text": "screen settled"],
        ]

        let rendered = ToolOutput.summarised(blocks)

        #expect(rendered.contains("tapped the button"))
        #expect(rendered.contains("screen settled"))
        #expect(rendered.contains("[image omitted: image/jpeg, 4 encoded bytes]"))
    }

    @Test("a plain string output passes through untouched")
    func aPlainStringOutputPassesThroughUntouched() {
        #expect(ToolOutput.summarised("Package.swift") == "Package.swift")
    }

    @Test("an output that is neither string nor blocks is rendered as data")
    func anOutputThatIsNeitherStringNorBlocksIsRenderedAsData() {
        #expect(ToolOutput.summarised(["exit": 1]).contains("\"exit\":1"))
    }

    @Test("nothing at all renders as nothing")
    func nothingAtAllRendersAsNothing() {
        #expect(ToolOutput.summarised(nil).isEmpty)
    }
}
