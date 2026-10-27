//
//  Configuration.swift
//  Harmony
//
//  Created by Aaron Pearce on 8/06/23.
//

import Foundation
import GRDB

public struct Configuration: Sendable {
    let cloudKitContainerIdentifier: String?
    let sharedAppGroupContainerIdentifier: String?
    let databasePath: String?
    let databaseConfiguration: GRDB.Configuration?

    /// Called synchronously from sync callbacks. The sink must enqueue work promptly
    /// and must not call back into Harmony. Nil disables sink delivery only;
    /// structured OSLog output remains enabled.
    public let diagnosticSink: (@Sendable (SyncDiagnosticEvent) -> Void)?

    internal var isDummy: Bool = false

    public init(
        cloudKitContainerIdentifier: String? = nil,
        sharedAppGroupContainerIdentifier: String? = nil,
        databasePath: String? = nil,
        databaseConfiguration: GRDB.Configuration? = nil,
        diagnosticSink: (@Sendable (SyncDiagnosticEvent) -> Void)? = nil
    ) {
        self.cloudKitContainerIdentifier = cloudKitContainerIdentifier
        self.sharedAppGroupContainerIdentifier = sharedAppGroupContainerIdentifier
        self.databasePath = databasePath
        self.databaseConfiguration = databaseConfiguration
        self.diagnosticSink = diagnosticSink
    }
}
