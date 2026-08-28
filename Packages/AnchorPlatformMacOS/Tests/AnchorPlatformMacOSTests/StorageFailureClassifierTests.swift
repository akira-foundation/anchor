import AnchorDomain
import AnchorPlatformMacOS
import AnchorStorage
import Foundation
import Testing

@Suite("Deciding which storage failures are worth repeating")
struct StorageFailureClassifierTests {
    @Test("a transport failure is worth repeating")
    func aTransportFailureIsWorthRepeating() {
        #expect(StorageFailureClassifier().isWorthRetrying(StorageFailure.transportUnavailable))
    }

    @Test(
        "a failure that repeating cannot fix is not repeated",
        arguments: [StorageFailure.accountUnavailable, .quotaExceeded]
    )
    func aFailureThatRepeatingCannotFixIsNotRepeated(_ failure: StorageFailure) {
        #expect(StorageFailureClassifier().isWorthRetrying(failure) == false)
    }

    @Test("a failure from somewhere other than storage is not repeated")
    func aFailureFromSomewhereOtherThanStorageIsNotRepeated() {
        #expect(
            StorageFailureClassifier().isWorthRetrying(NSError(domain: "anchor.test", code: 1))
                == false)
    }
}
