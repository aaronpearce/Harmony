//
//  Harmonic+CRUD.swift
//  Harmony
//
//  Created by Aaron Pearce on 11/06/23.
//

import Foundation
import GRDB
import CloudKit
import os.log

public extension Harmonic {

    func read<T>(_ block: (Database) throws -> T) throws -> T {
        try reader.read(block)
    }

    func read<T>(_ block: @Sendable @escaping (Database) throws -> T) async throws -> T {
        try await reader.read { db in
            try block(db)
        }
    }

    func create<T: HRecord>(record: T) async throws {
        try await database.write { db in
            try record.insert(db)
        }

        queueSaves(for: [record])
    }
    
    func create<T: HRecord>(records: [T]) async throws {
        try await database.write { db in
            try records.forEach {
                try $0.insert(db)
            }
        }
        queueSaves(for: records)
    }

    func save<T: HRecord>(record: T) async throws {
        try await database.write { db in
            try record.save(db)
        }

        queueSaves(for: [record])
    }

    func save<T: HRecord>(records: [T]) async throws {
        _ = try await database.write { db in
            try records.forEach {
                try $0.save(db)
            }
        }

        queueSaves(for: records)
    }

    /// Writes saves and deletions of different record types in one local transaction.
    /// CloudKit changes and local-resource cleanup run only after it commits.
    func write(saving recordsToSave: [any HRecord], deleting recordsToDelete: [any HRecord]) async throws {
        guard !recordsToSave.isEmpty || !recordsToDelete.isEmpty else { return }

        try await database.write { db in
            for record in recordsToSave {
                try record.save(db)
            }
            for record in recordsToDelete {
                try record.delete(db)
            }
        }

        if !recordsToSave.isEmpty {
            queueSaves(for: recordsToSave)
        }
        if !recordsToDelete.isEmpty {
            queueDeletions(for: recordsToDelete)
            removeLocalResources(for: recordsToDelete)
        }
    }

    func delete<T: HRecord>(record: T) async throws {
        _ = try await database.write { db in
            try record.delete(db)
        }

        queueDeletions(for: [record])
        removeLocalResources(for: [record])
    }

    func delete<T: HRecord>(records: [T]) async throws {
        _ = try await database.write { db in
            try records.forEach {
                try $0.delete(db)
            }
        }

        queueDeletions(for: records)
        removeLocalResources(for: records)
    }

    /// Deletes different record types in one local transaction.
    ///
    /// This is useful for aggregate deletion, where dependants and their
    /// parent must be queued for CloudKit together.
    func delete(records: [any HRecord]) async throws {
        _ = try await database.write { db in
            try records.forEach {
                try $0.delete(db)
            }
        }

        queueDeletions(for: records)
        removeLocalResources(for: records)
    }

    /// Pushes all of the given record type to CloudKit
    /// This occurs regardless of changes.
    /// Sometimes used during migration for schema changes.
    func pushAll<T: HRecord>(for recordType: T.Type) throws {
        let records = try read { db in
            return try recordType.fetchAll(db)
        }

        queueSaves(for: records)
    }

    private func queueSaves(for records: [any HRecord]) {
        Logger.database.info("Queuing saves")
        let pendingSaves: [CKSyncEngine.PendingRecordZoneChange] = records
            .unique(by: \.recordID)
            .map {
                .saveRecord($0.recordID)
            }

        self.syncEngine.state.add(pendingRecordZoneChanges: pendingSaves)
    }

    private func queueDeletions(for records: [any HRecord]) {
        Logger.database.info("Queuing deletions")
        let pendingDeletions: [CKSyncEngine.PendingRecordZoneChange] = records
            .unique(by: \.recordID)
            .map {
                .deleteRecord($0.recordID)
            }

        self.syncEngine.state.add(pendingRecordZoneChanges: pendingDeletions)
    }

    func sendChanges() async throws {
        try await self.syncEngine.sendChanges()
    }

    func fetchChanges() async throws {
        try await self.syncEngine.fetchChanges()
    }
}

extension Harmonic {
    func removeLocalResources(for records: [any HRecord]) {
        for record in records {
            do {
                try record.removeLocalResources()
            } catch {
                Logger.database.error(
                    "Failed to remove local resources for \(record.recordID): \(error.localizedDescription)"
                )
            }
        }
    }
}

private extension Sequence {
    func unique<T: Hashable>(by keyForValue: (Iterator.Element) throws -> T) rethrows -> [Iterator.Element] {
        var seen: Set<T> = []
        return try filter { try seen.insert(keyForValue($0)).inserted }
    }
}
