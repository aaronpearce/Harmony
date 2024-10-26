//
//  DatabaseWriter+WriteDeferred.swift
//  Harmony
//
//  Created by Aaron Pearce on 26/10/2024.
//

import GRDB

/// 
extension DatabaseWriter {
    func writeWithDeferredForeignKeys(_ updates: (Database) throws -> Void) throws {
        try writeWithoutTransaction { db in
            // Disable foreign keys
            try db.execute(sql: "PRAGMA foreign_keys = OFF");

            do {
                // Perform updates in a transaction
                try db.inTransaction {
                    try updates(db)

                    // Check foreign keys before commit
//                    if try Row.fetchOne(db, sql: "PRAGMA foreign_key_check") != nil {
//                        throw DatabaseError(resultCode: .SQLITE_CONSTRAINT_FOREIGNKEY)
//                    }

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
