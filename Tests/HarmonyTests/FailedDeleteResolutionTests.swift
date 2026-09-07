import CloudKit
import Testing
@testable import Harmony

struct FailedDeleteResolutionTests {
    @Test(arguments: [CKError.Code.unknownItem, .zoneNotFound])
    func missingServerDataAlreadySatisfiesDeletion(_ errorCode: CKError.Code) {
        #expect(Harmonic.failedDeleteResolution(for: errorCode) == .alreadyDeleted)
    }

    @Test(arguments: [
        CKError.Code.networkFailure,
        .networkUnavailable,
        .zoneBusy,
        .serviceUnavailable,
        .notAuthenticated,
        .operationCancelled,
        .requestRateLimited
    ])
    func syncEngineRetainsRetryableDeletes(_ errorCode: CKError.Code) {
        #expect(Harmonic.failedDeleteResolution(for: errorCode) == .syncEngineRetries)
    }

    @Test(arguments: [CKError.Code.serverRecordChanged, .batchRequestFailed])
    func recoverableDeleteFailuresAreRequeued(_ errorCode: CKError.Code) {
        #expect(Harmonic.failedDeleteResolution(for: errorCode) == .retry)
    }

    @Test
    func permanentDeleteFailureIsReportedWithoutAnInfiniteRetry() {
        #expect(Harmonic.failedDeleteResolution(for: .permissionFailure) == .report)
    }
}
