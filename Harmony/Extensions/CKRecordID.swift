//
//  CKRecordID.swift
//  Harmony
//
//  Created by Aaron Pearce on 11/06/23.
//

import Foundation
import CloudKit

extension CKRecord.ID {
    var parsedRecordType: String? {
        if let recordType = recordName
            .split(separator: "|", maxSplits: 1)
            .first {
            return String(recordType)
        } else {
            return nil
        }
    }

    var parsedRecordID: String? {
        if let recordID = recordName
            .split(separator: "|", maxSplits: 1)
            .last {
            return String(recordID)
        } else {
            return nil
        }
    }
}
