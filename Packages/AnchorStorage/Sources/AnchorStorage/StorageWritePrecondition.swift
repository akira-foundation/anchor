public enum StorageWritePrecondition: Sendable, Hashable {
    case none
    case objectIsAbsent
    case versionTagMatches(StorageVersionTag)
}
