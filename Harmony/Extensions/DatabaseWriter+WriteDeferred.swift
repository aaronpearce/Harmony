//
//  DatabaseWriter+WriteDeferred.swift
//  Harmony
//
//  Created by Aaron Pearce on 26/10/2024.
//

import GRDB

/// We use this within Harmony to save when receiving a record from CloudKit.
/// This aids us in avoiding foreign key constraint failures.
/// CloudKit doesn't guarantee order of records so we can receive children of a relationship before we receive the parent which can cause issues.
/// By doing this, we can ignore those and get to eventual consistency in theory.
extension DatabaseWriter {
    func writeWithDeferredForeignKeys(_ updates: (Database) throws -> Void) throws {
        try writeWithoutTransaction { db in
            // Disable foreign keys
            try db.execute(sql: "PRAGMA foreign_keys = OFF");

            do {
                // Perform updates in a transaction
                try db.inTransaction {
                    try updates(db)

                    return .commit
                }

                // Re-enable foreign keys
                try db.execute(sql: "PRAGMA foreign_keys = ON");
            } catch {
                // Re-enable foreign keys and rethrow
                try db.execute(sql: "PRAGMA foreign_keys = ON");
                throw error
            }
        }
    }
}
