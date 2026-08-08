import Foundation
import Testing

@testable import AnchorDomain

@Suite("Workspace")
struct WorkspaceTests {
    @Test("a workspace without a local repository is valid")
    func workspaceWithoutALocalRepositoryIsValid() {
        let workspace = Workspace(
            id: WorkspaceID(),
            projectID: ProjectID(),
            deviceID: DeviceID(),
            localRepositoryURL: nil
        )

        #expect(workspace.localRepositoryURL == nil)
    }

    @Test("two workspaces for the same project on different devices are distinct")
    func twoWorkspacesForTheSameProjectOnDifferentDevicesAreDistinct() {
        let sharedProjectID = ProjectID()
        let laptopWorkspace = Workspace(
            id: WorkspaceID(),
            projectID: sharedProjectID,
            deviceID: DeviceID(),
            localRepositoryURL: URL(filePath: "/Users/kid/Developer/anchor")
        )
        let desktopWorkspace = Workspace(
            id: WorkspaceID(),
            projectID: sharedProjectID,
            deviceID: DeviceID(),
            localRepositoryURL: URL(filePath: "/Users/kid/Code/anchor-v2")
        )

        #expect(laptopWorkspace != desktopWorkspace)
        #expect(laptopWorkspace.projectID == desktopWorkspace.projectID)
    }
}
