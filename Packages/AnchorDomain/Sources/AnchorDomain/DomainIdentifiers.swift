import AnchorFoundation

public enum ProjectSubject: Sendable {}
public enum DeviceSubject: Sendable {}
public enum WorkspaceSubject: Sendable {}
public enum SessionSubject: Sendable {}
public enum ToolActivitySubject: Sendable {}
public enum ArtifactSubject: Sendable {}
public enum RevisionSubject: Sendable {}
public enum ConversationMessageSubject: Sendable {}
public enum KnowledgeEntrySubject: Sendable {}
public enum SyncOperationSubject: Sendable {}

public typealias ProjectID = Identifier<ProjectSubject>
public typealias DeviceID = Identifier<DeviceSubject>
public typealias WorkspaceID = Identifier<WorkspaceSubject>
public typealias SessionID = Identifier<SessionSubject>
public typealias ToolActivityID = Identifier<ToolActivitySubject>
public typealias ArtifactID = Identifier<ArtifactSubject>
public typealias RevisionID = Identifier<RevisionSubject>
public typealias MessageID = Identifier<ConversationMessageSubject>
public typealias KnowledgeEntryID = Identifier<KnowledgeEntrySubject>
public typealias SyncOperationID = Identifier<SyncOperationSubject>
