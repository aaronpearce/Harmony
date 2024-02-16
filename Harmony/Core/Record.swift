//
//  HRecord.swift
//  CloudSyncTest
//
//  Created by Aaron Pearce on 14/07/21.
//

import GRDB
import Foundation
import CloudKit

public protocol CloudKitEncodable: Encodable {}

public protocol CloudKitDecodable: Decodable {}

public protocol HRecord: CloudKitEncodable & CloudKitDecodable & FetchableRecord & PersistableRecord {

    // Required model values
    var id: UUID { get }
//    var isDeleted: Bool { get set }

    // CloudKit values
    var archivedRecordData: Data? { get set }
    var archivedRecord: CKRecord? { get }
    
    static var recordType: String { get }
    var zoneID: CKRecordZone.ID { get }

    var recordID: CKRecord.ID { get }
    var record: CKRecord { get }
    
    var cloudKitLastModifiedDate: Date? { get }
    
    static func parseFrom(record: CKRecord) -> Self?
    
    mutating func updateChanges(db: Database, ckRecord: CKRecord) throws
}

extension HRecord {
    public var archivedRecord: CKRecord? {
        get {
            guard let data = archivedRecordData,
                  let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else {
                return nil
            }

            unarchiver.requiresSecureCoding = true
            return CKRecord(coder: unarchiver)
        }
        set {
            if let newValue {
                let archiver = NSKeyedArchiver(requiringSecureCoding: true)
                newValue.encodeSystemFields(with: archiver)
                self.archivedRecordData = archiver.encodedData
            } else {
                self.archivedRecordData = nil
            }
        }
    }
    
    public static var recordType: String {
        String(describing: self)
    }

    public var recordID: CKRecord.ID {
        CKRecord.ID(
            recordName: "\(Self.recordType)|\(id.uuidString)",
            zoneID: zoneID
        )
    }

    public var cloudKitLastModifiedDate: Date? {
        archivedRecord?.modificationDate
    }
    
    public var cloudKitCreationDate: Date? {
        archivedRecord?.creationDate
    }
    
    public static func parseFrom(record: CKRecord) -> Self? {
        try? CKRecordDecoder().decode(Self.self, from: record)
    }

    public mutating func updateChanges(db: Database, ckRecord: CKRecord) throws {
        if let cloudRecord = Self.parseFrom(record: ckRecord) {
            try cloudRecord.updateChanges(db, from: self)
        }
    }

    mutating func setLastKnownRecordIfNewer(_ otherRecord: CKRecord) {
        let localRecord = self.archivedRecord
        if let localDate = localRecord?.modificationDate {
            if let otherDate = otherRecord.modificationDate, localDate < otherDate {
                self.archivedRecord = otherRecord
            } else {
                // The other record is older than the one we already have.
            }
        } else {
            self.archivedRecord = otherRecord
        }
    }
}
