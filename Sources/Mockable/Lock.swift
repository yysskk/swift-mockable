import Foundation
#if canImport(Synchronization)
import Synchronization
#endif

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
    public func withLock<Result>(_ body: (inout sending Value) throws -> sending Result) rethrows -> sending Result {
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
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
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
public final class MockableLock<Value>: @unchecked Sendable {
    private let _box: _LockBoxBase<Value>

    public init(_ initialValue: Value) {
        #if canImport(Synchronization)
        if #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) {
            self._box = MutexLockBox(initialValue)
        } else {
            self._box = LegacyLockBox(initialValue)
        }
        #else
        self._box = LegacyLockBox(initialValue)
        #endif
    }

    @discardableResult
    public func withLock<Result>(_ body: (inout sending Value) throws -> sending Result) rethrows -> sending Result {
        try _box.withLock(body)
    }
}
