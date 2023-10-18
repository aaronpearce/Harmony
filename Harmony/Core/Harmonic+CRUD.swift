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

    func delete<T: HRecord>(record: T) async throws {
        _ = try await database.write { db in
            try record.delete(db)
        }

        queueDeletions(for: [record])
    }

    func delete<T: HRecord>(records: [T]) async throws {
        _ = try await database.write { db in
            try records.forEach {
                try $0.delete(db)
            }
        }

        queueDeletions(for: records)
    }

    private func queueSaves(for records: [any HRecord]) {
        Logger.database.info("Queuing saves")
        let pendingSaves: [CKSyncEngine.PendingRecordZoneChange] = records.map { 
            .saveRecord($0.recordID)
        }

        self.syncEngine.state.add(pendingRecordZoneChanges: pendingSaves)
    }

    private func queueDeletions(for records: [any HRecord]) {
        Logger.database.info("Queuing deletions")
        let pendingDeletions: [CKSyncEngine.PendingRecordZoneChange] = records.map {
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
