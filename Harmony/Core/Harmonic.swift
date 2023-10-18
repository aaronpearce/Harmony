//
//  Harmony.swift
//  Harmony
//
//  Created by Aaron Pearce on 8/06/23.
//

import SwiftUI
import CloudKit
import os.log
import GRDB
import Combine

///
/// Harmony becomes your central repository.
/// Every write and read goes via it.
///
/// Existing GRDB users can pass in their database file path if they wish
/// Harmony will take the following configuration options
/// - recordTypes: [HRecord.Type]
/// - configuration: Configuration
///     - cloudKitContainerIdentifier: String
///     - sharedAppGroupIdentifier: String
///     - databasePath: String ??
///     - databaseConfiguration: GRDB.Configuration
/// - migrator: GRDB.Migrator
///
/// Writing will be done via similar methods to the
/// GRDB.DatabaseWriter protocol with syntatic sugar for
/// HRecord.
///
/// Harmony will then manage all syncing and DB management
/// internally, removing the need for the system to observe
/// the database in any manner and also removing the
/// possiblity for a user to write directly to the database
/// without inherently misusing the library.
///
///
public final class Harmonic {

    // Containers
    // Shared or private?
    let configuration: Configuration

    /// The sync engine being used to sync.
    /// This is lazily initialized. You can re-initialize the sync engine by setting `_syncEngine` to nil then calling `self.syncEngine`.
    var _syncEngine: CKSyncEngine?
    var syncEngine: CKSyncEngine {
        if _syncEngine == nil {
            self.initializeSyncEngine()
        }
        return _syncEngine!
    }

    private let modelTypes: [any HRecord.Type]
    private let container: CKContainer
    private let userDefaults: UserDefaults
    let database: DatabaseWriter

    public var reader: DatabaseReader {
        database
    }

    public var databaseChanged: DatabasePublishers.DatabaseRegion {
        DatabaseRegionObservation(
            tracking: .fullDatabase
        ).publisher(in: database)
    }

    private var privateDatabase: CKDatabase {
        container.privateCloudDatabase
    }

    private var lastStateSerialization: CKSyncEngine.State.Serialization? {
        get {
            if let data = userDefaults.data(forKey: Keys.stateSerialization),
               let state = try? CKSyncEngine.State.Serialization.decode(data) {
                return state
            } else {
                return nil
            }
        }
        set {
            if let data = try? newValue?.encode() {
                userDefaults.set(data, forKey: Keys.stateSerialization)
            }
        }
    }

    public init(for modelTypes: [any HRecord.Type], configuration: Configuration, migrator: DatabaseMigrator) {
        self.modelTypes = modelTypes

        // Don't know if we actually need to store this for later.
        self.configuration = configuration

        if let cloudKitContainerIdentifier = configuration.cloudKitContainerIdentifier {
            self.container = CKContainer(identifier: cloudKitContainerIdentifier)
        } else {
            self.container = .default()
        }

        if let sharedAppGroupContainerIdentifier = configuration.sharedAppGroupContainerIdentifier {
            self.userDefaults = UserDefaults(suiteName: sharedAppGroupContainerIdentifier)!
        } else {
            self.userDefaults = .standard
        }

        if configuration.isDummy {
            self.database = try! DatabaseQueue()
        } else {

            do {

                let databasePath = try configuration.databasePath ?? Self.defaultDatabasePath

                let databaseConfiguration = configuration.databaseConfiguration ?? Self.makeDatabaseConfiguration()

                self.database = try DatabasePool(
                    path: databasePath,
                    configuration: databaseConfiguration
                )

                try migrator.migrate(self.database)
            } catch {
                fatalError("Unresolved error \(error)")
            }

            // Lazily start.
            initializeSyncEngine()

            Task {
                try? await syncEngine.fetchChanges()
            }
        }
    }

    static func dummy() -> Harmonic {
        var config = Configuration()
        config.isDummy = true
        let migrator = DatabaseMigrator()
        return Harmonic(for: [], configuration: config, migrator: migrator)
    }
}

private extension Harmonic {

    func initializeSyncEngine() {
        var configuration = CKSyncEngine.Configuration(
            database: self.container.privateCloudDatabase,
            stateSerialization: self.lastStateSerialization,
            delegate: self
        )
        configuration.automaticallySync = true //self.automaticallySync
        let syncEngine = CKSyncEngine(configuration)
        _syncEngine = syncEngine
        Logger.database.log("Initialized sync engine: \(syncEngine)")
    }
}

// MARK: CKSyncEngineDelegate

extension Harmonic: CKSyncEngineDelegate {

    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {

        Logger.database.log("Handling event \(event, privacy: .public)")

        switch event {
        case .stateUpdate(let stateUpdate):
            self.lastStateSerialization = stateUpdate.stateSerialization

        case .accountChange(let event):
            self.handleAccountChange(event)

        case .fetchedDatabaseChanges(let event):
            self.handleFetchedDatabaseChanges(event)

        case .fetchedRecordZoneChanges(let event):
            self.handleFetchedRecordZoneChanges(event)

        case .sentRecordZoneChanges(let event):
            self.handleSentRecordZoneChanges(event)

        case .sentDatabaseChanges:
            // The sample app doesn't track sent database changes in any meaningful way, but this might be useful depending on your data model.
            break

        case .willFetchChanges, .willFetchRecordZoneChanges, .didFetchRecordZoneChanges, .didFetchChanges, .willSendChanges, .didSendChanges:
            // We don't do anything here in the sample app, but these events might be helpful if you need to do any setup/cleanup when sync starts/ends.
            break

        @unknown default:
            Logger.database.info("Received unknown event: \(event)")
        }
    }

    public func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        Logger.database.info("Returning next record change batch for context: \(context.description, privacy: .public)")

        let scope = context.options.scope
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }

        let batch = await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
            if let recordType = recordID.parsedRecordType,
               let internalID = recordID.parsedRecordID {
                // We can sync this.
                // Find this in our DB
                if let modelType = modelType(for: recordType),
                        let uuid = UUID(uuidString: internalID)
                        return try modelType.fetchOne(db, key: uuid)
                }) {
                    return record.record
                } else {
                    // Could be a deletion?
                    syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
                    return nil
                }
            } else {
                syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
                return nil
            }
        }

        return batch
    }
}

// MARK: - Event Handlers
private extension Harmonic {

    func handleAccountChange(_ event: CKSyncEngine.Event.AccountChange) {
        Logger.database.info("Handle account change \(event, privacy: .public)")
    }

    func handleFetchedDatabaseChanges(_ event: CKSyncEngine.Event.FetchedDatabaseChanges) {
        Logger.database.info("Handle fetched database changes \(event, privacy: .public)")

        // If a zone was deleted, we should delete everything for that zone locally.
        #warning("Zone deletion is not handled!")
        /* Copied from the example sync sample from Apple
        var needsToSave = false
        for deletion in event.deletions {
            switch deletion.zoneID.zoneName {
            case Contact.zoneName:
                self.appData.contacts = [:]
                needsToSave = true
            default:
                Logger.database.info("Received deletion for unknown zone: \(deletion.zoneID)")
            }
        }

        if needsToSave {
            try? self.persistLocalData() // This error should be handled, but we'll skip that for brevity in this sample app.
        }
         */
    }

    func handleFetchedRecordZoneChanges(_ event: CKSyncEngine.Event.FetchedRecordZoneChanges) {
        Logger.database.info("Handle fetched record zone changes \(event)")

        var deferredRecords = [any HRecord]()
        for modification in event.modifications {
            // The sync engine fetched a record, and we want to merge it into our local persistence.
            // If we already have this object locally, let's merge the data from the server.
            // Otherwise, let's create a new local object.
            let record = modification.record
            if let id = record.recordID.parsedRecordID,
               let modelType = modelType(for: record) {
                try! database.write { db in
                    if var localRecord = try modelType.fetchOne(db, key: UUID(uuidString: id)) {
                        try localRecord.updateChanges(db: db, ckRecord: record)
                    } else {
                        if let model = modelType.parseFrom(record: record) {
                            // By catching `SQLITE_CONSTRAINT_FOREIGNKEY` it allows us to defer this records to the end of this batch.
                            // This will fail to handle if the parent record isn't in the same batch. Maybe a instance-wide "deferred" array to check each time.
                            // Alternatively, we could use this method and just YOLO it into the database anyway.
                            // https://github.com/groue/GRDB.swift/issues/172
                            do {
                                try model.save(db)
                            } catch ResultCode.SQLITE_CONSTRAINT_FOREIGNKEY {
                                // Defer and try again later
                                deferredRecords.append(model)
                            } catch {
                                throw error
                            }
                        }
                    }
                }
            }
        }

        for deferredRecord in deferredRecords {
            try? database.write { db in
                try deferredRecord.save(db)
            }
        }

        for deletion in event.deletions {

            // A record was deleted on the server, so let's remove it from our local persistence.
            let recordID = deletion.recordID
            if let recordType = recordID.parsedRecordType,
                let id = recordID.parsedRecordID,
               let modelType = modelType(for: recordType) {
                // Find it locally and merge it
                _ = try! database.write { db in
                    try modelType.deleteOne(db, key: UUID(uuidString: id))
                }
            }
        }

        // If we had any changes, let's save to disk.
        if !event.modifications.isEmpty || !event.deletions.isEmpty {
            // Already saved above... but maybe we should save at the end of a batch?
        }
    }

    func handleSentRecordZoneChanges(_ event: CKSyncEngine.Event.SentRecordZoneChanges) {
        Logger.database.info("Handle sent record zone changes \(event, privacy: .public)")

        // If we failed to save a record, we might want to retry depending on the error code.
        var newPendingRecordZoneChanges = [CKSyncEngine.PendingRecordZoneChange]()
        var newPendingDatabaseChanges = [CKSyncEngine.PendingDatabaseChange]()

        // Update the last known server record for each of the saved records.
        for savedRecord in event.savedRecords {
            if let id = savedRecord.recordID.parsedRecordID,
               let modelType = modelType(for: savedRecord) {
                try! database.write { db in
                    var localRecord = try? modelType.fetchOne(db, key: UUID(uuidString: id))
                    localRecord?.setLastKnownRecordIfNewer(savedRecord)
                    try! localRecord?.save(db)
                }
            }
        }

        // Handle any failed record saves.
        for failedRecordSave in event.failedRecordSaves {
            let failedRecord = failedRecordSave.record
            guard let id = failedRecord.recordID.parsedRecordID,
                let modelType = modelType(for: failedRecord) else {
                continue
            }

            var shouldClearServerRecord = false
            switch failedRecordSave.error.code {

            case .serverRecordChanged:
                // Let's merge the record from the server into our own local copy.
                // The `mergeFromServerRecord` function takes care of the conflict resolution.
                guard let serverRecord = failedRecordSave.error.serverRecord else {
                    Logger.database.error("No server record for conflict \(failedRecordSave.error)")
                    continue
                }

                try? database.write { db in
                    var localRecord = try modelType.fetchOne(db, key: UUID(uuidString: id))
                    // Merge from server...
                    try localRecord?.updateChanges(db: db, ckRecord: serverRecord)
                    try localRecord?.save(db)
                }

                newPendingRecordZoneChanges.append(.saveRecord(failedRecord.recordID))

            case .zoneNotFound:
                // Looks like we tried to save a record in a zone that doesn't exist.
                // Let's save that zone and retry saving the record.
                // Also clear the last known server record if we have one, it's no longer valid.
                let zone = CKRecordZone(zoneID: failedRecord.recordID.zoneID)
                newPendingDatabaseChanges.append(.saveZone(zone))
                newPendingRecordZoneChanges.append(.saveRecord(failedRecord.recordID))
                shouldClearServerRecord = true

            case .unknownItem:
                // We tried to save a record with a locally-cached server record, but that record no longer exists on the server.
                // This might mean that another device deleted the record, but we still have the data for that record locally.
                // We have the choice of either deleting the local data or re-uploading the local data.
                // For this sample app, let's re-upload the local data.
                newPendingRecordZoneChanges.append(.saveRecord(failedRecord.recordID))
                shouldClearServerRecord = true

            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .notAuthenticated, .operationCancelled:
                // There are several errors that the sync engine will automatically retry, let's just log and move on.
                Logger.database.debug("Retryable error saving \(failedRecord.recordID): \(failedRecordSave.error)")

            default:
                // We got an error, but we don't know what it is or how to handle it.
                // If you have any sort of telemetry system, you should consider tracking this scenario so you can understand which errors you see in the wild.
                Logger.database.fault("Unknown error saving record \(failedRecord.recordID): \(failedRecordSave.error)")
            }

            if shouldClearServerRecord {
                try? database.write { db in
                    var localRecord = try? modelType.fetchOne(db, key: UUID(uuidString: id))
                    // Merge from server...
                    localRecord?.archivedRecord = nil
                    try localRecord?.save(db)
                }
            }
        }

        if !newPendingDatabaseChanges.isEmpty {
            self.syncEngine.state.add(pendingDatabaseChanges: newPendingDatabaseChanges)
        }

        if !newPendingRecordZoneChanges.isEmpty {
            self.syncEngine.state.add(pendingRecordZoneChanges: newPendingRecordZoneChanges)
        }
    }
}


// MARK: - Model Type Helpers

private extension Harmonic {

    func modelType(for record: CKRecord) -> (any HRecord.Type)? {
        return modelType(for: record.recordType)
    }

    func modelType(for recordType: String) -> (any HRecord.Type)? {
        guard let modelType = self.modelTypes.first(where: { t in
            t.recordType == recordType
        }) else {
            return nil
        }

        return modelType
    }
}
