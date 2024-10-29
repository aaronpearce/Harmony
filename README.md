# Harmony

Harmony provides CloudKit sync for GRDB and only GRDB.

**Requirements:** iOS 17.0+, macOS 14.0+, tvOS 17.0+, watchOS 10.0+.

I am open to feedback to style, functionality and other contributions.

## Usage

After installing via Swift Package Manager and enabling CloudKit for your app, add the following to your `App.swift` or equivalent to initialize Harmony. 

```
@Harmony(
    records: [Model1.self, Model2.self],
    configuration: Harmony.Configuration(
            cloudKitContainerIdentifier:  "xxx" \\ Or leave nil for your default container.
            ),
    migrator: // Your GRDB DatabaseMigrator
) var harmony
```

You can then access your Harmony instance from anywhere for writing or reading by simply using:

```
@Harmony var harmony
```

Harmony provides access to write methods that will automatically sync to CloudKit and hides direct database writing access for this purpose. If you write via another means to your GRDB database, Harmony will not see those changes.

Harmony also provides direct access to your `DatabaseReader` if you wish to read directly. I highly suggest seeing if GRDBQuery will fit your needs first. 

### Foreign Keys

Harmony does not support usage of foreign keys in GRDB. This is due to CloudKit being a system of eventual consistency. Records can return in sets where they don't have the related data within the same set or out of order. Foreign keys are incompatible with this style of system so we have taken the choice to not support foreign keys after many attempts to do so.
