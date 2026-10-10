import AnchorApplication
import AnchorPersistence
import AnchorStoredContext

public enum ContextPublicationAssembly {
    public static func makePublication(
        database: SQLiteDatabase, storage: AssembledContextStorage
    ) -> PublishProjectContextAction? {
        guard let remote = storage.remote else { return nil }

        let publisher = StoredContextPublisher(remote: remote, ledger: storage.local)
        return PublishProjectContextAction(
            reader: PersistentPublishableContextReader(database: database),
            projects: publisher, artifacts: publisher, knowledge: publisher)
    }
}
