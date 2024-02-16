//
//  Configuration.swift
//  Harmony
//
//  Created by Aaron Pearce on 8/06/23.
//

import Foundation
import GRDB

public struct Configuration: Sendable{
    let cloudKitContainerIdentifier: String?
    let sharedAppGroupContainerIdentifier: String?
    let databasePath: String?
    let databaseConfiguration: GRDB.Configuration?

    internal var isDummy: Bool = false

    public init(cloudKitContainerIdentifier: String? = nil, sharedAppGroupContainerIdentifier: String? = nil,
        databasePath: String? = nil,
        databaseConfiguration: GRDB.Configuration? = nil
    ) {
        self.cloudKitContainerIdentifier = cloudKitContainerIdentifier
        self.sharedAppGroupContainerIdentifier = sharedAppGroupContainerIdentifier
        self.databasePath = databasePath
        self.databaseConfiguration = databaseConfiguration
    }
}
