import Foundation
#if canImport(Synchronization)
import Synchronization
#endif

/// A thread-safe lock wrapper for platforms without the Synchronization module.
/// Provides the same `withLock` API as `Mutex` for API compatibility.
///
/// This type is used on iOS 17 and earlier, while `Mutex` is used on iOS 18+.
final class LegacyLock<Value>: @unchecked Sendable {
    private var _value: Value
    private let _lock = NSLock()

    init(_ initialValue: Value) {
        self._value = initialValue
    }

    @discardableResult
    func withLock<Result>(_ body: (inout sending Value) throws -> sending Result) rethrows -> sending Result {
        _lock.lock()
        defer { _lock.unlock() }
        return try body(&_value)
    }
}

private class _LockBoxBase<Value>: @unchecked Sendable {
    @discardableResult
    func withLock<Result>(_ body: (inout sending Value) throws -> sending Result) rethrows -> sending Result {
        fatalError("Unimplemented lock box")
    }
}

private final class LegacyLockBox<Value>: _LockBoxBase<Value>, @unchecked Sendable {
    private let _lock: LegacyLock<Value>

    init(_ initialValue: Value) {
        self._lock = LegacyLock(initialValue)
    }

    override func withLock<Result>(_ body: (inout sending Value) throws -> sending Result) rethrows -> sending Result {
        try _lock.withLock(body)
    }
}

#if canImport(Synchronization)
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
private final class MutexLockBox<Value>: _LockBoxBase<Value>, @unchecked Sendable {
    private let _lock: Mutex<Value>

    init(_ initialValue: Value) {
        nonisolated(unsafe) let initialValue = initialValue
        self._lock = Mutex(initialValue)
    }

    override func withLock<Result>(_ body: (inout sending Value) throws -> sending Result) rethrows -> sending Result {
        try _lock.withLock(body)
    }
}
#endif

/// A best-available lock wrapper that prefers `Mutex` on supported OS versions
/// and falls back to `LegacyLock` on older deployment targets.
///
/// `MockableLock` is used in generated mocks for `Sendable` protocols to provide
/// thread-safe access to mutable state.
///
/// This type is `public` only so that macro-generated code can reference it from
/// the client module; it is not intended to be used directly.
///
/// - On iOS 18.0+ / macOS 15.0+ / tvOS 18.0+ / watchOS 11.0+ / visionOS 2.0+, uses `Mutex` from the `Synchronization` module.
/// - On older deployment targets, falls back to an `NSLock`-based implementation.
@_documentation(visibility: internal)
public final class MockableLock<Value>: @unchecked Sendable {
    private let _box: _LockBoxBase<Value>

    /// Creates a new lock wrapping the given initial value.
    ///
    /// - Parameter initialValue: The value to protect with the lock.
    public init(_ initialValue: Value) {
        #if canImport(Synchronization)
        if #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *) {
            self._box = MutexLockBox(initialValue)
        } else {
            self._box = LegacyLockBox(initialValue)
        }
        #else
        self._box = LegacyLockBox(initialValue)
        #endif
    }

    /// Calls the given closure while holding the lock, providing mutable access to the protected value.
    ///
    /// - Parameter body: A closure that can read and modify the protected value.
    /// - Returns: The value returned by the closure.
    @discardableResult
    public func withLock<Result>(_ body: (inout sending Value) throws -> sending Result) rethrows -> sending Result {
        try _box.withLock(body)
    }
}
