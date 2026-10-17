import Foundation

/// A synchronous, one-time initialization shared by startup and CRUD callers.
/// The factory must not recursively access this same storage.
final class LockedLazy<Value> {
    private let lock = NSLock()
    private var value: Value?

    func get(_ makeValue: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        if let value { return value }
        let newValue = makeValue()
        value = newValue
        return newValue
    }
}

// The lock protects construction/storage; a Sendable value may safely be
// returned to callers after that lock is released.
extension LockedLazy: @unchecked Sendable where Value: Sendable {}
