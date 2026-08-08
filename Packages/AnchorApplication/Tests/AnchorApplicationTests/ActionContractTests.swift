import AnchorDomain
import Testing

@testable import AnchorApplication

private struct EchoProjectIDAction: Action {
    func perform(_ projectID: ProjectID) async throws -> ProjectID {
        projectID
    }
}

@Suite("Action contract")
struct ActionContractTests {
    @Test("an action returns the output produced from its input")
    func actionReturnsTheOutputProducedFromItsInput() async throws {
        let expectedProjectID = ProjectID()
        let echoAction = EchoProjectIDAction()

        let returnedProjectID = try await echoAction.perform(expectedProjectID)

        #expect(returnedProjectID == expectedProjectID)
    }
}
