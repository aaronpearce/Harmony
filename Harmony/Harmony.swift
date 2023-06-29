//
//  Harmony.swift
//
//
//  Created by Aaron Pearce on 14/06/23.
//

import Foundation
import GRDB

@propertyWrapper
public struct Harmony {
    static var current: Harmonic = .dummy()

    public var wrappedValue: Harmonic {
        get { Self.current }
    }

    static var hasBeenInitialized = false

    public init() {
        if !Self.hasBeenInitialized {
            fatalError("Ensure your first usage of @Harmonic initializes the system.")
        }
    }

    public init(records modelTypes: [any HRecord.Type], configuration: Configuration, migrator: DatabaseMigrator) {

        guard !Self.hasBeenInitialized else {
            fatalError("Do not try to initialize @Harmonic twice!")
        }

        Self.current = Harmonic(for: modelTypes, configuration: configuration, migrator: migrator)
        Self.hasBeenInitialized = true
    }
}
