//
//  StateSerialization+Encoder.swift
//  
//
//  Created by Aaron Pearce on 22/06/23.
//

import CloudKit

extension CKSyncEngine.State.Serialization {

    func encode() throws -> Data? {
        return try JSONEncoder().encode(self)
    }

    static func decode(_ data: Data) throws -> Self? {
        return try JSONDecoder().decode(Self.self, from: data)
    }
}
