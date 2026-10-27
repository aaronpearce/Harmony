import CloudKit
import Foundation
import os.log

extension Harmonic {
    /// Both destinations receive the same allowlisted fields. A nil sink never
    /// suppresses OSLog, and no raw records or error descriptions are logged here.
    func recordDiagnostic(_ event: SyncDiagnosticEvent) {
        let level: OSLogType
        switch event.level {
        case .debug: level = .debug
        case .info: level = .info
        case .notice: level = .default
        case .warning, .error: level = .error
        case .fault: level = .fault
        }

        let errorCode = event.errorCode.map { String($0) } ?? "-"
        let retryAfter = event.retryAfterSeconds.map { String($0) } ?? "-"
        let saved = event.saved.map { String($0) } ?? "-"
        let deleted = event.deleted.map { String($0) } ?? "-"
        let failed = event.failed.map { String($0) } ?? "-"
        let pending = event.pending.map { String($0) } ?? "-"

        Logger.database.log(
            level: level,
            """
            event=\(event.kind.rawValue, privacy: .public) \
            severity=\(event.level.rawValue, privacy: .public) \
            scope=\(event.scope, privacy: .public) \
            operation=\(event.operation?.rawValue ?? "-", privacy: .public) \
            recordType=\(event.recordType ?? "-", privacy: .public) \
            errorDomain=\(event.errorDomain ?? "-", privacy: .public) \
            errorCode=\(errorCode, privacy: .public) \
            retryAfterSeconds=\(retryAfter, privacy: .public) \
            recovery=\(event.recovery?.rawValue ?? "-", privacy: .public) \
            saved=\(saved, privacy: .public) \
            deleted=\(deleted, privacy: .public) \
            failed=\(failed, privacy: .public) \
            pending=\(pending, privacy: .public)
            """
        )

        configuration.diagnosticSink?(event)
    }

    func withDiagnostics<T>(
        operation: SyncDiagnosticEvent.Operation,
        recordType: String? = nil,
        _ action: () throws -> T
    ) rethrows -> T {
        do {
            return try action()
        } catch {
            recordDiagnostic(.init(
                kind: .operationFailed,
                level: .error,
                operation: operation,
                recordType: recordType,
                error: error
            ))

            throw error
        }
    }

    func recordDiagnostics(for event: CKSyncEngine.Event, engine: CKSyncEngine) {
        let pending = engine.state.pendingRecordZoneChanges.count

        switch event {
        case .stateUpdate: break // Checkpoint success/failure is logged at persistence.

        case .accountChange:
            recordDiagnostic(.init(kind: .accountChanged))

        case .willFetchChanges:
            recordDiagnostic(.init(
                kind: .fetchStarted,
                pending: pending
            ))

        case .didFetchChanges:
            recordDiagnostic(.init(
                kind: .fetchFinished,
                pending: pending
            ))

        case .willFetchRecordZoneChanges:
            recordDiagnostic(.init(kind: .zoneFetchStarted))

        case .didFetchRecordZoneChanges(let change):
            recordDiagnostic(.init(
                kind: .zoneFetchFinished,
                level: change.error == nil ? .info : .error,
                operation: .fetch,
                error: change.error
            ))

        case .willSendChanges:
            recordDiagnostic(.init(
                kind: .sendStarted,
                pending: pending
            ))

        case .didSendChanges:
            recordDiagnostic(.init(
                kind: .sendFinished,
                pending: pending
            ))

        case .fetchedDatabaseChanges(let change):
            recordDiagnostic(.init(
                kind: .zonesFetched,
                saved: change.modifications.count,
                deleted: change.deletions.count
            ))

        case .fetchedRecordZoneChanges(let change):
            recordDiagnostic(.init(
                kind: .recordsFetched,
                saved: change.modifications.count,
                deleted: change.deletions.count
            ))

        case .sentDatabaseChanges(let change):
            recordDiagnostic(.init(
                kind: .zonesSent,
                saved: change.savedZones.count,
                deleted: change.deletedZoneIDs.count,
                failed: change.failedZoneSaves.count + change.failedZoneDeletes.count
            ))

            for failure in change.failedZoneSaves {
                recordDiagnostic(.init(
                    kind: .operationFailed,
                    level: .error,
                    operation: .zoneSave,
                    error: failure.error
                ))
            }

            for error in change.failedZoneDeletes.values {
                recordDiagnostic(.init(
                    kind: .operationFailed,
                    level: .error,
                    operation: .zoneDelete,
                    error: error
                ))
            }

        case .sentRecordZoneChanges(let change):
            recordDiagnostic(.init(
                kind: .recordsSent,
                saved: change.savedRecords.count,
                deleted: change.deletedRecordIDs.count,
                failed: change.failedRecordSaves.count + change.failedRecordDeletes.count,
                pending: pending
            ))

        @unknown default:
            recordDiagnostic(.init(
                kind: .unknownEvent,
                level: .warning
            ))
        }
    }
}
