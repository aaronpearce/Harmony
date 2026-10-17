import CloudKit
import os.log

extension Harmonic {
    /// Only a successful lookup that finds no local row can discard a save.
    /// Returning nil after an error skips this batch but preserves the pending
    /// change for the next sync attempt.
    static func recordToUpload(
        recordID: CKRecord.ID,
        fetch: () async throws -> CKRecord?,
        removePendingSave: () -> Void
    ) async -> CKRecord? {
        do {
            let record = try await fetch()
            if record == nil {
                removePendingSave()
            }
            return record
        } catch {
            Logger.database.error("Unable to read pending record \(recordID); retaining upload: \(error.localizedDescription)")
            return nil
        }
    }
}
