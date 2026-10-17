import CloudKit
import Foundation
import GRDB
import Testing
@testable import Harmony

struct SyncRecoveryTests {
    @Test
    func concurrentEngineAccessInitializesExactlyOnce() {
        let storage = LockedLazy<NSObject>()
        let results = LockedResults()
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            let value = storage.get {
                results.recordInitialization()
                return NSObject()
            }
            results.append(value)
        }
        #expect(results.initializationCount == 1)
        let first = results.values.first!
        #expect(results.values.allSatisfy { $0 === first })
    }

    @Test
    func startupAccessDoesNotReplacePreviouslyQueuedState() {
        let storage = LockedLazy<NSMutableArray>()
        let earlyCaller = storage.get { NSMutableArray() }
        earlyCaller.add("pending upload")
        let startupCaller = storage.get { NSMutableArray() }
        #expect(startupCaller === earlyCaller)
        #expect(startupCaller.count == 1)
    }

    @Test
    func readFailurePreservesPendingUploadAndNextHealthyReadSuppliesIt() async {
        let record = CKRecord(recordType: "TestRecord")
        var pending = true
        let failedResult = await Harmonic.recordToUpload(
            recordID: record.recordID,
            fetch: { throw TestError.databaseUnavailable },
            removePendingSave: { pending = false }
        )
        #expect(failedResult == nil)
        #expect(pending)

        let retryResult = await Harmonic.recordToUpload(
            recordID: record.recordID,
            fetch: { record },
            removePendingSave: { pending = false }
        )
        #expect(retryResult === record)
        #expect(pending)
    }

    @Test
    func successfulMissingRowLookupRemovesPendingUpload() async {
        let id = CKRecord.ID(recordName: "missing")
        var pending = true
        let result = await Harmonic.recordToUpload(
            recordID: id,
            fetch: { nil },
            removePendingSave: { pending = false }
        )
        #expect(result == nil)
        #expect(!pending)
    }

    @Test
    func delayedDeleteAcknowledgementPreservesRecreatedRowAndResources() throws {
        let harmonic = try makeDatabase()
        let id = UUID()
        let resource = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: resource) }
        try Data("replacement resource".utf8).write(to: resource)
        let old = TestRecord(id: id, value: "old", resourcePath: nil)
        let replacement = TestRecord(id: id, value: "replacement", resourcePath: resource.path)
        // The local part of explicit deletion commits before CloudKit replies.
        try harmonic.database.write { db in
            try old.insert(db)
            try old.delete(db)
            try replacement.insert(db)
        }
        harmonic.handleSentRecordZoneChanges(
            savedRecords: [], deletedRecordIDs: [old.recordID],
            failedRecordDeletes: [:], failedRecordSaves: []
        )
        let actual = try harmonic.read { try TestRecord.fetchOne($0, key: id) }
        #expect(actual?.value == "replacement")
        #expect(FileManager.default.fileExists(atPath: resource.path))
    }

    @Test
    func ordinaryDeleteAcknowledgementLeavesRowAbsent() throws {
        let harmonic = try makeDatabase()
        let old = TestRecord(id: UUID(), value: "old", resourcePath: nil)
        try harmonic.database.write { db in
            try old.insert(db)
            try old.delete(db)
        }
        harmonic.handleSentRecordZoneChanges(
            savedRecords: [], deletedRecordIDs: [old.recordID],
            failedRecordDeletes: [:], failedRecordSaves: []
        )
        let actual = try harmonic.read { try TestRecord.fetchOne($0, key: old.id) }
        #expect(actual == nil)
    }

    private func makeDatabase() throws -> Harmonic {
        var config = Configuration()
        config.isDummy = true
        let harmonic = Harmonic(for: [TestRecord.self], configuration: config, migrator: DatabaseMigrator())
        try harmonic.database.write { db in
            try db.create(table: TestRecord.databaseTableName) { table in
                table.column("id", .blob).primaryKey()
                table.column("value", .text).notNull()
                table.column("resourcePath", .text)
                table.column("archivedRecordData", .blob)
            }
        }
        return harmonic
    }
}

private enum TestError: Error { case databaseUnavailable }

private struct TestRecord: HRecord {
    var id: UUID
    var value: String
    var resourcePath: String?
    var archivedRecordData: Data? = nil
    var zoneID: CKRecordZone.ID { CKRecordZone.ID(zoneName: "test") }
    var record: CKRecord { CKRecord(recordType: Self.recordType, recordID: recordID) }
    func removeLocalResources() throws {
        if let resourcePath { try FileManager.default.removeItem(atPath: resourcePath) }
    }
}

private final class LockedResults: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var initializationCount = 0
    private(set) var values: [NSObject] = []
    func recordInitialization() {
        lock.lock()
        defer { lock.unlock() }
        initializationCount += 1
    }
    func append(_ value: NSObject) {
        lock.lock()
        defer { lock.unlock() }
        values.append(value)
    }
}
