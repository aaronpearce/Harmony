import CloudKit
import Foundation

/// An allowlisted diagnostic event. Never contains records, account identifiers,
/// localized error descriptions, or error userInfo.
public struct SyncDiagnosticEvent: Codable, Sendable {
    public enum Level: String, Codable, Sendable {
        case debug
        case info
        case notice
        case warning
        case error
        case fault
    }

    public enum Kind: String, Codable, Sendable {
        case engineInitialized, checkpointSaved, checkpointFailed, accountChanged
        case fetchStarted, fetchFinished, zoneFetchStarted, zoneFetchFinished
        case sendStarted, sendFinished, zonesFetched, zonesSent, recordsFetched, recordsSent
        case recordsQueued, batchPrepared, recordSkipped, operationFailed, unknownEvent
    }

    public enum Operation: String, Codable, Sendable {
        case checkpoint, initialUpload, fetch, send, prepareUpload, importRecord
        case save, delete, zoneSave, zoneDelete, cleanup
    }

    public enum Recovery: String, Codable, Sendable {
        case systemRetry, requeue, alreadyDeleted, unhandled, discarded
    }

    public let timestamp: Date
    public let level: Level
    public let kind: Kind
    public let scope: String
    public let operation: Operation?
    public let recordType: String?
    public let saved: Int?
    public let deleted: Int?
    public let failed: Int?
    public let pending: Int?
    public let errorDomain: String?
    public let errorCode: Int?
    public let retryAfterSeconds: Double?
    public let recovery: Recovery?

    public init(
        kind: Kind,
        level: Level = .info,
        operation: Operation? = nil,
        recordType: String? = nil,
        saved: Int? = nil,
        deleted: Int? = nil,
        failed: Int? = nil,
        pending: Int? = nil,
        error: Error? = nil,
        recovery: Recovery? = nil
    ) {
        self.timestamp = Date()
        self.level = level
        self.kind = kind
        self.scope = "private"
        self.operation = operation
        self.recordType = recordType.map { String($0.prefix(128)) }
        self.saved = saved
        self.deleted = deleted
        self.failed = failed
        self.pending = pending
        self.recovery = recovery

        if let error {
            let nsError = error as NSError
            // Custom domains can contain arbitrary text. Persist only known domains.
            self.errorDomain = [CKError.errorDomain, NSCocoaErrorDomain, NSURLErrorDomain]
                .contains(nsError.domain) ? nsError.domain : "Other"
            self.errorCode = nsError.code
            let delay = (error as? CKError)?.retryAfterSeconds
            self.retryAfterSeconds = delay.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        } else {
            self.errorDomain = nil
            self.errorCode = nil
            self.retryAfterSeconds = nil
        }
    }
}
