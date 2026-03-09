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

    public init(_ initialValue: Value) {
        self._value = initialValue
    }

    #if compiler(>=6.0)
    @discardableResult
    public func withLock<Result>(_ body: (inout sending Value) throws -> sending Result) rethrows -> sending Result {
        _lock.lock()
        defer { _lock.unlock() }
        return try body(&_value)
    }
    #else
    @discardableResult
    public func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        _lock.lock()
        defer { _lock.unlock() }
        return try body(&_value)
    }
    #endif
}

private class _LockBoxBase<Value>: @unchecked Sendable {
    #if compiler(>=6.0)
    @discardableResult
    func withLock<Result>(_ body: (inout sending Value) throws -> sending Result) rethrows -> sending Result {
        fatalError("Unimplemented lock box")
    }
    #else
    @discardableResult
    func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        fatalError("Unimplemented lock box")
    }
    #endif
}

private final class LegacyLockBox<Value>: _LockBoxBase<Value>, @unchecked Sendable {
    private let _lock: LegacyLock<Value>

    init(_ initialValue: Value) {
        self._lock = LegacyLock(initialValue)
    }

    #if compiler(>=6.0)
    override func withLock<Result>(_ body: (inout sending Value) throws -> sending Result) rethrows -> sending Result {
        try _lock.withLock(body)
    }
    #else
    override func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        try _lock.withLock(body)
    }
    #endif
}

#if compiler(>=6.0) && canImport(Synchronization)
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
        #if compiler(>=6.0) && canImport(Synchronization)
        if #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) {
            self._box = MutexLockBox(initialValue)
        } else {
            self._box = LegacyLockBox(initialValue)
        }
        #else
        self._box = LegacyLockBox(initialValue)
        #endif
    }

    #if compiler(>=6.0)
    @discardableResult
    public func withLock<Result>(_ body: (inout sending Value) throws -> sending Result) rethrows -> sending Result {
        try _box.withLock(body)
    }
    #else
    @discardableResult
    public func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        try _box.withLock(body)
    }
    #endif
}
