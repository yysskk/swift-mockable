import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import MockableMacros

@Suite("Subscript Macro Tests")
struct SubscriptMacroTests {
    private let testMacros: [String: Macro.Type] = [
        "Mockable": MockableMacro.self
    ]

    @Test("Protocol with get-only subscript")
    func getOnlySubscript() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Cache {
                subscript(key: String) -> Int { get }
            }
            """,
            expandedSource: """
            protocol Cache {
                subscript(key: String) -> Int { get }
            }

            #if DEBUG
            public class CacheMock: Cache {
                public var subscriptStringCallCount: Int = 0
                public var subscriptStringCallArgs: [String] = []
                public var subscriptStringHandler: (@Sendable (String) -> Int )? = nil
                public subscript(key: String) -> Int {
                    subscriptStringCallCount += 1
                    subscriptStringCallArgs.append(key)
                    guard let _handler = subscriptStringHandler else {
                        fatalError("\\(Self.self).subscriptStringHandler is not set")
                    }
                    return _handler(key)
                }
                public func resetMock() {
                    subscriptStringCallCount = 0
                    subscriptStringCallArgs = []
                    subscriptStringHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with get-set subscript")
    func getSetSubscript() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Storage {
                subscript(index: Int) -> String { get set }
            }
            """,
            expandedSource: """
            protocol Storage {
                subscript(index: Int) -> String { get set }
            }

            #if DEBUG
            public class StorageMock: Storage {
                public var subscriptIntCallCount: Int = 0
                public var subscriptIntCallArgs: [Int] = []
                public var subscriptIntHandler: (@Sendable (Int) -> String )? = nil
                public var subscriptIntSetHandler: (@Sendable (Int, String ) -> Void)? = nil
                public subscript(index: Int) -> String {
                    get {
                        subscriptIntCallCount += 1
                        subscriptIntCallArgs.append(index)
                        guard let _handler = subscriptIntHandler else {
                            fatalError("\\(Self.self).subscriptIntHandler is not set")
                        }
                        return _handler(index)
                    }
                    set {
                        if let _handler = subscriptIntSetHandler {
                            _handler(index, newValue)
                        }
                    }
                }
                public func resetMock() {
                    subscriptIntCallCount = 0
                    subscriptIntCallArgs = []
                    subscriptIntHandler = nil
                    subscriptIntSetHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with multi-parameter subscript")
    func multiParameterSubscript() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Matrix {
                subscript(row: Int, column: Int) -> Double { get set }
            }
            """,
            expandedSource: """
            protocol Matrix {
                subscript(row: Int, column: Int) -> Double { get set }
            }

            #if DEBUG
            public class MatrixMock: Matrix {
                public var subscriptIntIntCallCount: Int = 0
                public var subscriptIntIntCallArgs: [(row: Int, column: Int)] = []
                public var subscriptIntIntHandler: (@Sendable ((row: Int, column: Int)) -> Double )? = nil
                public var subscriptIntIntSetHandler: (@Sendable ((row: Int, column: Int), Double ) -> Void)? = nil
                public subscript(row: Int, column: Int) -> Double {
                    get {
                        subscriptIntIntCallCount += 1
                        subscriptIntIntCallArgs.append((row: row, column: column))
                        guard let _handler = subscriptIntIntHandler else {
                            fatalError("\\(Self.self).subscriptIntIntHandler is not set")
                        }
                        return _handler((row: row, column: column))
                    }
                    set {
                        if let _handler = subscriptIntIntSetHandler {
                            _handler((row: row, column: column), newValue)
                        }
                    }
                }
                public func resetMock() {
                    subscriptIntIntCallCount = 0
                    subscriptIntIntCallArgs = []
                    subscriptIntIntHandler = nil
                    subscriptIntIntSetHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with multiple subscript overloads")
    func multipleSubscriptOverloads() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Collection {
                subscript(index: Int) -> String { get }
                subscript(key: String) -> Int { get set }
            }
            """,
            expandedSource: """
            protocol Collection {
                subscript(index: Int) -> String { get }
                subscript(key: String) -> Int { get set }
            }

            #if DEBUG
            public class CollectionMock: Collection {
                public var subscriptIntCallCount: Int = 0
                public var subscriptIntCallArgs: [Int] = []
                public var subscriptIntHandler: (@Sendable (Int) -> String )? = nil
                public subscript(index: Int) -> String {
                    subscriptIntCallCount += 1
                    subscriptIntCallArgs.append(index)
                    guard let _handler = subscriptIntHandler else {
                        fatalError("\\(Self.self).subscriptIntHandler is not set")
                    }
                    return _handler(index)
                }
                public var subscriptStringCallCount: Int = 0
                public var subscriptStringCallArgs: [String] = []
                public var subscriptStringHandler: (@Sendable (String) -> Int )? = nil
                public var subscriptStringSetHandler: (@Sendable (String, Int ) -> Void)? = nil
                public subscript(key: String) -> Int {
                    get {
                        subscriptStringCallCount += 1
                        subscriptStringCallArgs.append(key)
                        guard let _handler = subscriptStringHandler else {
                            fatalError("\\(Self.self).subscriptStringHandler is not set")
                        }
                        return _handler(key)
                    }
                    set {
                        if let _handler = subscriptStringSetHandler {
                            _handler(key, newValue)
                        }
                    }
                }
                public func resetMock() {
                    subscriptIntCallCount = 0
                    subscriptIntCallArgs = []
                    subscriptIntHandler = nil
                    subscriptStringCallCount = 0
                    subscriptStringCallArgs = []
                    subscriptStringHandler = nil
                    subscriptStringSetHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Sendable protocol with get-only subscript")
    func sendableGetOnlySubscript() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol SendableCache: Sendable {
                subscript(key: String) -> Int { get }
            }
            """,
            expandedSource: """
            protocol SendableCache: Sendable {
                subscript(key: String) -> Int { get }
            }

            #if DEBUG
            #if canImport(Synchronization)
            @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
            public final class SendableCacheMock: SendableCache, Sendable {
                private struct Storage {
                    var subscriptStringCallCount: Int = 0
                    var subscriptStringCallArgs: [String] = []
                    var subscriptStringHandler: (@Sendable (String) -> Int )? = nil
                }
                private let _storage = Mutex<Storage>(Storage())
                public var subscriptStringCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.subscriptStringCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptStringCallCount = newValue
                        }
                    }
                }
                public var subscriptStringCallArgs: [String] {
                    get {
                        _storage.withLock {
                            $0.subscriptStringCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptStringCallArgs = newValue
                        }
                    }
                }
                public var subscriptStringHandler: (@Sendable (String) -> Int )? {
                    get {
                        _storage.withLock {
                            $0.subscriptStringHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptStringHandler = newValue
                        }
                    }
                }
                public subscript(key: String) -> Int {
                    _storage.withLock { storage in
                        storage.subscriptStringCallCount += 1
                        storage.subscriptStringCallArgs.append(key)
                    }
                    let _handler = _storage.withLock {
                        $0.subscriptStringHandler
                    }
                    guard let _handler else {
                        fatalError("\\(Self.self).subscriptStringHandler is not set")
                    }
                    return _handler(key)
                }
                public func resetMock() {
                    _storage.withLock { storage in
                        storage.subscriptStringCallCount = 0
                        storage.subscriptStringCallArgs = []
                        storage.subscriptStringHandler = nil
                    }
                }
            }
            #else
            public final class SendableCacheMock: SendableCache, Sendable {
                private struct Storage {
                    var subscriptStringCallCount: Int = 0
                    var subscriptStringCallArgs: [String] = []
                    var subscriptStringHandler: (@Sendable (String) -> Int )? = nil
                }
                private let _storage = LegacyLock<Storage>(Storage())
                public var subscriptStringCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.subscriptStringCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptStringCallCount = newValue
                        }
                    }
                }
                public var subscriptStringCallArgs: [String] {
                    get {
                        _storage.withLock {
                            $0.subscriptStringCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptStringCallArgs = newValue
                        }
                    }
                }
                public var subscriptStringHandler: (@Sendable (String) -> Int )? {
                    get {
                        _storage.withLock {
                            $0.subscriptStringHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptStringHandler = newValue
                        }
                    }
                }
                public subscript(key: String) -> Int {
                    _storage.withLock { storage in
                        storage.subscriptStringCallCount += 1
                        storage.subscriptStringCallArgs.append(key)
                    }
                    let _handler = _storage.withLock {
                        $0.subscriptStringHandler
                    }
                    guard let _handler else {
                        fatalError("\\(Self.self).subscriptStringHandler is not set")
                    }
                    return _handler(key)
                }
                public func resetMock() {
                    _storage.withLock { storage in
                        storage.subscriptStringCallCount = 0
                        storage.subscriptStringCallArgs = []
                        storage.subscriptStringHandler = nil
                    }
                }
            }
            #endif
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Sendable protocol with get-set subscript")
    func sendableGetSetSubscript() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol SendableStorage: Sendable {
                subscript(index: Int) -> String { get set }
            }
            """,
            expandedSource: """
            protocol SendableStorage: Sendable {
                subscript(index: Int) -> String { get set }
            }

            #if DEBUG
            #if canImport(Synchronization)
            @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
            public final class SendableStorageMock: SendableStorage, Sendable {
                private struct Storage {
                    var subscriptIntCallCount: Int = 0
                    var subscriptIntCallArgs: [Int] = []
                    var subscriptIntHandler: (@Sendable (Int) -> String )? = nil
                    var subscriptIntSetHandler: (@Sendable (Int, String ) -> Void)? = nil
                }
                private let _storage = Mutex<Storage>(Storage())
                public var subscriptIntCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.subscriptIntCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptIntCallCount = newValue
                        }
                    }
                }
                public var subscriptIntCallArgs: [Int] {
                    get {
                        _storage.withLock {
                            $0.subscriptIntCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptIntCallArgs = newValue
                        }
                    }
                }
                public var subscriptIntHandler: (@Sendable (Int) -> String )? {
                    get {
                        _storage.withLock {
                            $0.subscriptIntHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptIntHandler = newValue
                        }
                    }
                }
                public var subscriptIntSetHandler: (@Sendable (Int, String ) -> Void)? {
                    get {
                        _storage.withLock {
                            $0.subscriptIntSetHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptIntSetHandler = newValue
                        }
                    }
                }
                public subscript(index: Int) -> String {
                    get {
                        _storage.withLock { storage in
                            storage.subscriptIntCallCount += 1
                            storage.subscriptIntCallArgs.append(index)
                        }
                        let _handler = _storage.withLock {
                            $0.subscriptIntHandler
                        }
                        guard let _handler else {
                            fatalError("\\(Self.self).subscriptIntHandler is not set")
                        }
                        return _handler(index)
                    }
                    set {
                        if let _handler = _storage.withLock({ $0.subscriptIntSetHandler
                            }) {
                            _handler(index, newValue)
                        }
                    }
                }
                public func resetMock() {
                    _storage.withLock { storage in
                        storage.subscriptIntCallCount = 0
                        storage.subscriptIntCallArgs = []
                        storage.subscriptIntHandler = nil
                        storage.subscriptIntSetHandler = nil
                    }
                }
            }
            #else
            public final class SendableStorageMock: SendableStorage, Sendable {
                private struct Storage {
                    var subscriptIntCallCount: Int = 0
                    var subscriptIntCallArgs: [Int] = []
                    var subscriptIntHandler: (@Sendable (Int) -> String )? = nil
                    var subscriptIntSetHandler: (@Sendable (Int, String ) -> Void)? = nil
                }
                private let _storage = LegacyLock<Storage>(Storage())
                public var subscriptIntCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.subscriptIntCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptIntCallCount = newValue
                        }
                    }
                }
                public var subscriptIntCallArgs: [Int] {
                    get {
                        _storage.withLock {
                            $0.subscriptIntCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptIntCallArgs = newValue
                        }
                    }
                }
                public var subscriptIntHandler: (@Sendable (Int) -> String )? {
                    get {
                        _storage.withLock {
                            $0.subscriptIntHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptIntHandler = newValue
                        }
                    }
                }
                public var subscriptIntSetHandler: (@Sendable (Int, String ) -> Void)? {
                    get {
                        _storage.withLock {
                            $0.subscriptIntSetHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptIntSetHandler = newValue
                        }
                    }
                }
                public subscript(index: Int) -> String {
                    get {
                        _storage.withLock { storage in
                            storage.subscriptIntCallCount += 1
                            storage.subscriptIntCallArgs.append(index)
                        }
                        let _handler = _storage.withLock {
                            $0.subscriptIntHandler
                        }
                        guard let _handler else {
                            fatalError("\\(Self.self).subscriptIntHandler is not set")
                        }
                        return _handler(index)
                    }
                    set {
                        if let _handler = _storage.withLock({ $0.subscriptIntSetHandler
                            }) {
                            _handler(index, newValue)
                        }
                    }
                }
                public func resetMock() {
                    _storage.withLock { storage in
                        storage.subscriptIntCallCount = 0
                        storage.subscriptIntCallArgs = []
                        storage.subscriptIntHandler = nil
                        storage.subscriptIntSetHandler = nil
                    }
                }
            }
            #endif
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Actor protocol with get-only subscript")
    func actorGetOnlySubscript() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol ActorCache: Actor {
                subscript(key: String) -> Int { get }
            }
            """,
            expandedSource: """
            protocol ActorCache: Actor {
                subscript(key: String) -> Int { get }
            }

            #if DEBUG
            #if canImport(Synchronization)
            @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
            public actor ActorCacheMock: ActorCache {
                private struct Storage {
                    var subscriptStringCallCount: Int = 0
                    var subscriptStringCallArgs: [String] = []
                    var subscriptStringHandler: (@Sendable (String) -> Int )? = nil
                }
                private let _storage = Mutex<Storage>(Storage())
                public nonisolated var subscriptStringCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.subscriptStringCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptStringCallCount = newValue
                        }
                    }
                }
                public nonisolated var subscriptStringCallArgs: [String] {
                    get {
                        _storage.withLock {
                            $0.subscriptStringCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptStringCallArgs = newValue
                        }
                    }
                }
                public nonisolated var subscriptStringHandler: (@Sendable (String) -> Int )? {
                    get {
                        _storage.withLock {
                            $0.subscriptStringHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptStringHandler = newValue
                        }
                    }
                }
                public subscript(key: String) -> Int {
                    _storage.withLock { storage in
                        storage.subscriptStringCallCount += 1
                        storage.subscriptStringCallArgs.append(key)
                    }
                    let _handler = _storage.withLock {
                        $0.subscriptStringHandler
                    }
                    guard let _handler else {
                        fatalError("\\(Self.self).subscriptStringHandler is not set")
                    }
                    return _handler(key)
                }
                public nonisolated func resetMock() {
                    _storage.withLock { storage in
                        storage.subscriptStringCallCount = 0
                        storage.subscriptStringCallArgs = []
                        storage.subscriptStringHandler = nil
                    }
                }
            }
            #else
            public actor ActorCacheMock: ActorCache {
                private struct Storage {
                    var subscriptStringCallCount: Int = 0
                    var subscriptStringCallArgs: [String] = []
                    var subscriptStringHandler: (@Sendable (String) -> Int )? = nil
                }
                private let _storage = LegacyLock<Storage>(Storage())
                public nonisolated var subscriptStringCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.subscriptStringCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptStringCallCount = newValue
                        }
                    }
                }
                public nonisolated var subscriptStringCallArgs: [String] {
                    get {
                        _storage.withLock {
                            $0.subscriptStringCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptStringCallArgs = newValue
                        }
                    }
                }
                public nonisolated var subscriptStringHandler: (@Sendable (String) -> Int )? {
                    get {
                        _storage.withLock {
                            $0.subscriptStringHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptStringHandler = newValue
                        }
                    }
                }
                public subscript(key: String) -> Int {
                    _storage.withLock { storage in
                        storage.subscriptStringCallCount += 1
                        storage.subscriptStringCallArgs.append(key)
                    }
                    let _handler = _storage.withLock {
                        $0.subscriptStringHandler
                    }
                    guard let _handler else {
                        fatalError("\\(Self.self).subscriptStringHandler is not set")
                    }
                    return _handler(key)
                }
                public nonisolated func resetMock() {
                    _storage.withLock { storage in
                        storage.subscriptStringCallCount = 0
                        storage.subscriptStringCallArgs = []
                        storage.subscriptStringHandler = nil
                    }
                }
            }
            #endif
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Actor protocol with get-set subscript")
    func actorGetSetSubscript() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol ActorStorage: Actor {
                subscript(index: Int) -> String { get set }
            }
            """,
            expandedSource: """
            protocol ActorStorage: Actor {
                subscript(index: Int) -> String { get set }
            }

            #if DEBUG
            #if canImport(Synchronization)
            @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
            public actor ActorStorageMock: ActorStorage {
                private struct Storage {
                    var subscriptIntCallCount: Int = 0
                    var subscriptIntCallArgs: [Int] = []
                    var subscriptIntHandler: (@Sendable (Int) -> String )? = nil
                    var subscriptIntSetHandler: (@Sendable (Int, String ) -> Void)? = nil
                }
                private let _storage = Mutex<Storage>(Storage())
                public nonisolated var subscriptIntCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.subscriptIntCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptIntCallCount = newValue
                        }
                    }
                }
                public nonisolated var subscriptIntCallArgs: [Int] {
                    get {
                        _storage.withLock {
                            $0.subscriptIntCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptIntCallArgs = newValue
                        }
                    }
                }
                public nonisolated var subscriptIntHandler: (@Sendable (Int) -> String )? {
                    get {
                        _storage.withLock {
                            $0.subscriptIntHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptIntHandler = newValue
                        }
                    }
                }
                public nonisolated var subscriptIntSetHandler: (@Sendable (Int, String ) -> Void)? {
                    get {
                        _storage.withLock {
                            $0.subscriptIntSetHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptIntSetHandler = newValue
                        }
                    }
                }
                public subscript(index: Int) -> String {
                    get {
                        _storage.withLock { storage in
                            storage.subscriptIntCallCount += 1
                            storage.subscriptIntCallArgs.append(index)
                        }
                        let _handler = _storage.withLock {
                            $0.subscriptIntHandler
                        }
                        guard let _handler else {
                            fatalError("\\(Self.self).subscriptIntHandler is not set")
                        }
                        return _handler(index)
                    }
                    set {
                        if let _handler = _storage.withLock({ $0.subscriptIntSetHandler
                            }) {
                            _handler(index, newValue)
                        }
                    }
                }
                public nonisolated func resetMock() {
                    _storage.withLock { storage in
                        storage.subscriptIntCallCount = 0
                        storage.subscriptIntCallArgs = []
                        storage.subscriptIntHandler = nil
                        storage.subscriptIntSetHandler = nil
                    }
                }
            }
            #else
            public actor ActorStorageMock: ActorStorage {
                private struct Storage {
                    var subscriptIntCallCount: Int = 0
                    var subscriptIntCallArgs: [Int] = []
                    var subscriptIntHandler: (@Sendable (Int) -> String )? = nil
                    var subscriptIntSetHandler: (@Sendable (Int, String ) -> Void)? = nil
                }
                private let _storage = LegacyLock<Storage>(Storage())
                public nonisolated var subscriptIntCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.subscriptIntCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptIntCallCount = newValue
                        }
                    }
                }
                public nonisolated var subscriptIntCallArgs: [Int] {
                    get {
                        _storage.withLock {
                            $0.subscriptIntCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptIntCallArgs = newValue
                        }
                    }
                }
                public nonisolated var subscriptIntHandler: (@Sendable (Int) -> String )? {
                    get {
                        _storage.withLock {
                            $0.subscriptIntHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptIntHandler = newValue
                        }
                    }
                }
                public nonisolated var subscriptIntSetHandler: (@Sendable (Int, String ) -> Void)? {
                    get {
                        _storage.withLock {
                            $0.subscriptIntSetHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptIntSetHandler = newValue
                        }
                    }
                }
                public subscript(index: Int) -> String {
                    get {
                        _storage.withLock { storage in
                            storage.subscriptIntCallCount += 1
                            storage.subscriptIntCallArgs.append(index)
                        }
                        let _handler = _storage.withLock {
                            $0.subscriptIntHandler
                        }
                        guard let _handler else {
                            fatalError("\\(Self.self).subscriptIntHandler is not set")
                        }
                        return _handler(index)
                    }
                    set {
                        if let _handler = _storage.withLock({ $0.subscriptIntSetHandler
                            }) {
                            _handler(index, newValue)
                        }
                    }
                }
                public nonisolated func resetMock() {
                    _storage.withLock { storage in
                        storage.subscriptIntCallCount = 0
                        storage.subscriptIntCallArgs = []
                        storage.subscriptIntHandler = nil
                        storage.subscriptIntSetHandler = nil
                    }
                }
            }
            #endif
            #endif
            """,
            macros: testMacros
        )
    }
}
