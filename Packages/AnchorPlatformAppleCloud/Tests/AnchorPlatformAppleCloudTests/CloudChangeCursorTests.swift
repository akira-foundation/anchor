import AnchorStorage
import Foundation
import Testing

@testable import AnchorPlatformAppleCloud

@Suite("Cloud change cursor")
struct CloudChangeCursorTests {
    @Test("a cursor survives being written down and read back")
    func cursorSurvivesBeingWrittenDownAndReadBack() {
        let token = Data("server-token".utf8)

        let resumePoint = CloudChangeCursor.resumePoint(
            from: CloudChangeCursor.cursor(pageToken: token, entryIndex: 3))

        #expect(resumePoint.pageToken == token)
        #expect(resumePoint.entriesToSkip == 4)
    }

    @Test("no cursor starts from the beginning of the log")
    func noCursorStartsFromTheBeginningOfTheLog() {
        let resumePoint = CloudChangeCursor.resumePoint(from: nil)

        #expect(resumePoint.pageToken == nil)
        #expect(resumePoint.entriesToSkip == 0)
    }

    @Test("a cursor taken before any page carries no token")
    func cursorTakenBeforeAnyPageCarriesNoToken() {
        let resumePoint = CloudChangeCursor.resumePoint(
            from: CloudChangeCursor.cursor(pageToken: nil, entryIndex: 0))

        #expect(resumePoint.pageToken == nil)
        #expect(resumePoint.entriesToSkip == 1)
    }

    @Test("a cursor that did not come from this provider is not trusted")
    func cursorThatDidNotComeFromThisProviderIsNotTrusted() {
        let resumePoint = CloudChangeCursor.resumePoint(
            from: StorageCursor(rawValue: "not-a-cursor"))

        #expect(resumePoint.pageToken == nil)
        #expect(resumePoint.entriesToSkip == 0)
    }
}
