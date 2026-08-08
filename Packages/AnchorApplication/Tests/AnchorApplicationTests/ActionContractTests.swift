import AnchorDomain
import Testing

@testable import AnchorApplication

private struct EchoProjectIdentifierAction: Action {
    func perform(_ projectIdentifier: ProjectIdentifier) async throws -> ProjectIdentifier {
        projectIdentifier
    }
}

@Suite("Action contract")
struct ActionContractTests {
    @Test("an action returns the output produced from its input")
    func actionReturnsTheOutputProducedFromItsInput() async throws {
        let expectedProjectIdentifier = ProjectIdentifier()
        let echoAction = EchoProjectIdentifierAction()

        let returnedProjectIdentifier = try await echoAction.perform(expectedProjectIdentifier)

        #expect(returnedProjectIdentifier == expectedProjectIdentifier)
    }
}
