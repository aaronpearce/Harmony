//
//  CKRecordID.swift
//  Harmony
//
//  Created by Aaron Pearce on 11/06/23.
//

import Foundation
import CloudKit

extension CKRecord.ID {
    func fullRecordID(with recordType: CKRecord.RecordType) -> CKRecord.ID {
        CKRecord.ID(
            recordName: "\(recordType)|\(recordName)",
            zoneID: zoneID
        )
    }
}
