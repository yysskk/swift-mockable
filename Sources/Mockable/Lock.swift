import Foundation

/// A thread-safe lock wrapper for platforms without the Synchronization module.
/// Provides the same `withLock` API as `Mutex` for API compatibility.
///
/// This type is used on iOS 17 and earlier, while `Mutex` is used on iOS 18+.
public final class LegacyLock<Value>: @unchecked Sendable {
    private var _value: Value
    private let _lock = NSLock()

    public init(_ initialValue: Value) {
        self._value = initialValue
    }

    @discardableResult
    public func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        _lock.lock()
        defer { _lock.unlock() }
        return try body(&_value)
    }
}
