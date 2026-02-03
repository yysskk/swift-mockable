import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import MockableMacros

@Suite("AssociatedType Macro Tests")
struct AssociatedTypeMacroTests {
    private let testMacros: [String: Macro.Type] = [
        "Mockable": MockableMacro.self
    ]

    @Test("Protocol with associated type without default")
    func associatedTypeWithoutDefault() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol DataStore {
                associatedtype Model
                func fetch() -> Model
                func save(_ model: Model)
            }
            """,
            expandedSource: """
            protocol DataStore {
                associatedtype Model
                func fetch() -> Model
                func save(_ model: Model)
            }

            #if DEBUG
            public class DataStoreMock: DataStore {
                public typealias Model = Any
                public var fetchCallCount: Int = 0
                public var fetchCallArgs: [()] = []
                public var fetchHandler: (@Sendable () -> Model)? = nil
                public func fetch() -> Model {
                    fetchCallCount += 1
                    fetchCallArgs.append(())
                    guard let _handler = fetchHandler else {
                        fatalError("\\(Self.self).fetchHandler is not set")
                    }
                    return _handler()
                }
                public var saveCallCount: Int = 0
                public var saveCallArgs: [Model] = []
                public var saveHandler: (@Sendable (Model) -> Void)? = nil
                public func save(_ model: Model) {
                    saveCallCount += 1
                    saveCallArgs.append(model)
                    if let _handler = saveHandler {
                        _handler(model)
                    }
                }
                public func resetMock() {
                    fetchCallCount = 0
                    fetchCallArgs = []
                    fetchHandler = nil
                    saveCallCount = 0
                    saveCallArgs = []
                    saveHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with associated type with default type")
    func associatedTypeWithDefault() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol StringStore {
                associatedtype Element = String
                func get() -> Element
            }
            """,
            expandedSource: """
            protocol StringStore {
                associatedtype Element = String
                func get() -> Element
            }

            #if DEBUG
            public class StringStoreMock: StringStore {
                public typealias Element = String
                public var getCallCount: Int = 0
                public var getCallArgs: [()] = []
                public var getHandler: (@Sendable () -> Element)? = nil
                public func get() -> Element {
                    getCallCount += 1
                    getCallArgs.append(())
                    guard let _handler = getHandler else {
                        fatalError("\\(Self.self).getHandler is not set")
                    }
                    return _handler()
                }
                public func resetMock() {
                    getCallCount = 0
                    getCallArgs = []
                    getHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with multiple associated types")
    func multipleAssociatedTypes() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Repository {
                associatedtype Entity
                associatedtype ID = String
                func find(by id: ID) -> Entity?
                func save(_ entity: Entity) -> ID
            }
            """,
            expandedSource: """
            protocol Repository {
                associatedtype Entity
                associatedtype ID = String
                func find(by id: ID) -> Entity?
                func save(_ entity: Entity) -> ID
            }

            #if DEBUG
            public class RepositoryMock: Repository {
                public typealias Entity = Any
                public typealias ID = String
                public var findCallCount: Int = 0
                public var findCallArgs: [ID] = []
                public var findHandler: (@Sendable (ID) -> Entity?)? = nil
                public func find(by id: ID) -> Entity? {
                    findCallCount += 1
                    findCallArgs.append(id)
                    guard let _handler = findHandler else {
                        fatalError("\\(Self.self).findHandler is not set")
                    }
                    return _handler(id)
                }
                public var saveCallCount: Int = 0
                public var saveCallArgs: [Entity] = []
                public var saveHandler: (@Sendable (Entity) -> ID)? = nil
                public func save(_ entity: Entity) -> ID {
                    saveCallCount += 1
                    saveCallArgs.append(entity)
                    guard let _handler = saveHandler else {
                        fatalError("\\(Self.self).saveHandler is not set")
                    }
                    return _handler(entity)
                }
                public func resetMock() {
                    findCallCount = 0
                    findCallArgs = []
                    findHandler = nil
                    saveCallCount = 0
                    saveCallArgs = []
                    saveHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Sendable protocol with associated type")
    func sendableProtocolWithAssociatedType() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol AsyncStore: Sendable {
                associatedtype Item = String
                func fetch() async -> Item
            }
            """,
            expandedSource: """
            protocol AsyncStore: Sendable {
                associatedtype Item = String
                func fetch() async -> Item
            }

            #if DEBUG
            #if canImport(Synchronization)
            @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
            public final class AsyncStoreMock: AsyncStore, Sendable {
                public typealias Item = String
                private struct Storage {
                    var fetchCallCount: Int = 0
                    var fetchCallArgs: [()] = []
                    var fetchHandler: (@Sendable () async -> Item)? = nil
                }
                private let _storage = Mutex<Storage>(Storage())
                public var fetchCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.fetchCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.fetchCallCount = newValue
                        }
                    }
                }
                public var fetchCallArgs: [()] {
                    get {
                        _storage.withLock {
                            $0.fetchCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.fetchCallArgs = newValue
                        }
                    }
                }
                public var fetchHandler: (@Sendable () async -> Item)? {
                    get {
                        _storage.withLock {
                            $0.fetchHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.fetchHandler = newValue
                        }
                    }
                }
                public func fetch() async -> Item {
                    let _handler = _storage.withLock { storage -> (@Sendable () async -> Item)? in
                        storage.fetchCallCount += 1
                        storage.fetchCallArgs.append(())
                        return storage.fetchHandler
                    }
                    guard let _handler else {
                        fatalError("\\(Self.self).fetchHandler is not set")
                    }
                    return await _handler()
                }
                public func resetMock() {
                    _storage.withLock { storage in
                        storage.fetchCallCount = 0
                        storage.fetchCallArgs = []
                        storage.fetchHandler = nil
                    }
                }
            }
            #else
            public final class AsyncStoreMock: AsyncStore, Sendable {
                public typealias Item = String
                private struct Storage {
                    var fetchCallCount: Int = 0
                    var fetchCallArgs: [()] = []
                    var fetchHandler: (@Sendable () async -> Item)? = nil
                }
                private let _storage = LegacyLock<Storage>(Storage())
                public var fetchCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.fetchCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.fetchCallCount = newValue
                        }
                    }
                }
                public var fetchCallArgs: [()] {
                    get {
                        _storage.withLock {
                            $0.fetchCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.fetchCallArgs = newValue
                        }
                    }
                }
                public var fetchHandler: (@Sendable () async -> Item)? {
                    get {
                        _storage.withLock {
                            $0.fetchHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.fetchHandler = newValue
                        }
                    }
                }
                public func fetch() async -> Item {
                    let _handler = _storage.withLock { storage -> (@Sendable () async -> Item)? in
                        storage.fetchCallCount += 1
                        storage.fetchCallArgs.append(())
                        return storage.fetchHandler
                    }
                    guard let _handler else {
                        fatalError("\\(Self.self).fetchHandler is not set")
                    }
                    return await _handler()
                }
                public func resetMock() {
                    _storage.withLock { storage in
                        storage.fetchCallCount = 0
                        storage.fetchCallArgs = []
                        storage.fetchHandler = nil
                    }
                }
            }
            #endif
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Actor protocol with associated type")
    func actorProtocolWithAssociatedType() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol CacheActor: Actor {
                associatedtype Value = Data
                func get(key: String) -> Value?
                func set(key: String, value: Value)
            }
            """,
            expandedSource: """
            protocol CacheActor: Actor {
                associatedtype Value = Data
                func get(key: String) -> Value?
                func set(key: String, value: Value)
            }

            #if DEBUG
            #if canImport(Synchronization)
            @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
            public actor CacheActorMock: CacheActor {
                public typealias Value = Data
                private struct Storage {
                    var getCallCount: Int = 0
                    var getCallArgs: [String] = []
                    var getHandler: (@Sendable (String) -> Value?)? = nil
                    var setCallCount: Int = 0
                    var setCallArgs: [(key: String, value: Value)] = []
                    var setHandler: (@Sendable ((key: String, value: Value)) -> Void)? = nil
                }
                private let _storage = Mutex<Storage>(Storage())
                public nonisolated var getCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.getCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.getCallCount = newValue
                        }
                    }
                }
                public nonisolated var getCallArgs: [String] {
                    get {
                        _storage.withLock {
                            $0.getCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.getCallArgs = newValue
                        }
                    }
                }
                public nonisolated var getHandler: (@Sendable (String) -> Value?)? {
                    get {
                        _storage.withLock {
                            $0.getHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.getHandler = newValue
                        }
                    }
                }
                public func get(key: String) -> Value? {
                    let _handler = _storage.withLock { storage -> (@Sendable (String) -> Value?)? in
                        storage.getCallCount += 1
                        storage.getCallArgs.append(key)
                        return storage.getHandler
                    }
                    guard let _handler else {
                        fatalError("\\(Self.self).getHandler is not set")
                    }
                    return _handler(key)
                }
                public nonisolated var setCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.setCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.setCallCount = newValue
                        }
                    }
                }
                public nonisolated var setCallArgs: [(key: String, value: Value)] {
                    get {
                        _storage.withLock {
                            $0.setCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.setCallArgs = newValue
                        }
                    }
                }
                public nonisolated var setHandler: (@Sendable ((key: String, value: Value)) -> Void)? {
                    get {
                        _storage.withLock {
                            $0.setHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.setHandler = newValue
                        }
                    }
                }
                public func set(key: String, value: Value) {
                    let _handler = _storage.withLock { storage -> (@Sendable ((key: String, value: Value)) -> Void)? in
                        storage.setCallCount += 1
                        storage.setCallArgs.append((key: key, value: value))
                        return storage.setHandler
                    }
                    if let _handler {
                        _handler((key: key, value: value))
                    }
                }
                public nonisolated func resetMock() {
                    _storage.withLock { storage in
                        storage.getCallCount = 0
                        storage.getCallArgs = []
                        storage.getHandler = nil
                        storage.setCallCount = 0
                        storage.setCallArgs = []
                        storage.setHandler = nil
                    }
                }
            }
            #else
            public actor CacheActorMock: CacheActor {
                public typealias Value = Data
                private struct Storage {
                    var getCallCount: Int = 0
                    var getCallArgs: [String] = []
                    var getHandler: (@Sendable (String) -> Value?)? = nil
                    var setCallCount: Int = 0
                    var setCallArgs: [(key: String, value: Value)] = []
                    var setHandler: (@Sendable ((key: String, value: Value)) -> Void)? = nil
                }
                private let _storage = LegacyLock<Storage>(Storage())
                public nonisolated var getCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.getCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.getCallCount = newValue
                        }
                    }
                }
                public nonisolated var getCallArgs: [String] {
                    get {
                        _storage.withLock {
                            $0.getCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.getCallArgs = newValue
                        }
                    }
                }
                public nonisolated var getHandler: (@Sendable (String) -> Value?)? {
                    get {
                        _storage.withLock {
                            $0.getHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.getHandler = newValue
                        }
                    }
                }
                public func get(key: String) -> Value? {
                    let _handler = _storage.withLock { storage -> (@Sendable (String) -> Value?)? in
                        storage.getCallCount += 1
                        storage.getCallArgs.append(key)
                        return storage.getHandler
                    }
                    guard let _handler else {
                        fatalError("\\(Self.self).getHandler is not set")
                    }
                    return _handler(key)
                }
                public nonisolated var setCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.setCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.setCallCount = newValue
                        }
                    }
                }
                public nonisolated var setCallArgs: [(key: String, value: Value)] {
                    get {
                        _storage.withLock {
                            $0.setCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.setCallArgs = newValue
                        }
                    }
                }
                public nonisolated var setHandler: (@Sendable ((key: String, value: Value)) -> Void)? {
                    get {
                        _storage.withLock {
                            $0.setHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.setHandler = newValue
                        }
                    }
                }
                public func set(key: String, value: Value) {
                    let _handler = _storage.withLock { storage -> (@Sendable ((key: String, value: Value)) -> Void)? in
                        storage.setCallCount += 1
                        storage.setCallArgs.append((key: key, value: value))
                        return storage.setHandler
                    }
                    if let _handler {
                        _handler((key: key, value: value))
                    }
                }
                public nonisolated func resetMock() {
                    _storage.withLock { storage in
                        storage.getCallCount = 0
                        storage.getCallArgs = []
                        storage.getHandler = nil
                        storage.setCallCount = 0
                        storage.setCallArgs = []
                        storage.setHandler = nil
                    }
                }
            }
            #endif
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with associated type with type constraint")
    func associatedTypeWithConstraint() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol DecodableStore {
                associatedtype Item: Decodable
                func decode(from data: Data) -> Item
            }
            """,
            expandedSource: """
            protocol DecodableStore {
                associatedtype Item: Decodable
                func decode(from data: Data) -> Item
            }

            #if DEBUG
            public class DecodableStoreMock: DecodableStore {
                public typealias Item = Any
                public var decodeCallCount: Int = 0
                public var decodeCallArgs: [Data] = []
                public var decodeHandler: (@Sendable (Data) -> Item)? = nil
                public func decode(from data: Data) -> Item {
                    decodeCallCount += 1
                    decodeCallArgs.append(data)
                    guard let _handler = decodeHandler else {
                        fatalError("\\(Self.self).decodeHandler is not set")
                    }
                    return _handler(data)
                }
                public func resetMock() {
                    decodeCallCount = 0
                    decodeCallArgs = []
                    decodeHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with associated type used in property")
    func associatedTypeInProperty() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol StateHolder {
                associatedtype State = String
                var currentState: State { get }
                var previousState: State? { get set }
            }
            """,
            expandedSource: """
            protocol StateHolder {
                associatedtype State = String
                var currentState: State { get }
                var previousState: State? { get set }
            }

            #if DEBUG
            public class StateHolderMock: StateHolder {
                public typealias State = String
                public var _currentState: State? = nil
                public var currentState: State {
                    _currentState!
                }
                public var previousState: State? = nil
                public func resetMock() {
                    _currentState = nil
                    previousState = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with associated type with complex default type")
    func associatedTypeWithComplexDefault() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol ArrayStore {
                associatedtype Element = [String: Int]
                func getAll() -> Element
            }
            """,
            expandedSource: """
            protocol ArrayStore {
                associatedtype Element = [String: Int]
                func getAll() -> Element
            }

            #if DEBUG
            public class ArrayStoreMock: ArrayStore {
                public typealias Element = [String: Int]
                public var getAllCallCount: Int = 0
                public var getAllCallArgs: [()] = []
                public var getAllHandler: (@Sendable () -> Element)? = nil
                public func getAll() -> Element {
                    getAllCallCount += 1
                    getAllCallArgs.append(())
                    guard let _handler = getAllHandler else {
                        fatalError("\\(Self.self).getAllHandler is not set")
                    }
                    return _handler()
                }
                public func resetMock() {
                    getAllCallCount = 0
                    getAllCallArgs = []
                    getAllHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with associated type in optional return type")
    func associatedTypeInOptionalReturn() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol OptionalFetcher {
                associatedtype Result
                func fetch(id: String) -> Result?
            }
            """,
            expandedSource: """
            protocol OptionalFetcher {
                associatedtype Result
                func fetch(id: String) -> Result?
            }

            #if DEBUG
            public class OptionalFetcherMock: OptionalFetcher {
                public typealias Result = Any
                public var fetchCallCount: Int = 0
                public var fetchCallArgs: [String] = []
                public var fetchHandler: (@Sendable (String) -> Result?)? = nil
                public func fetch(id: String) -> Result? {
                    fetchCallCount += 1
                    fetchCallArgs.append(id)
                    guard let _handler = fetchHandler else {
                        fatalError("\\(Self.self).fetchHandler is not set")
                    }
                    return _handler(id)
                }
                public func resetMock() {
                    fetchCallCount = 0
                    fetchCallArgs = []
                    fetchHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with associated type in array parameter")
    func associatedTypeInArrayParameter() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol BatchProcessor {
                associatedtype Item = Int
                func process(items: [Item]) -> Int
            }
            """,
            expandedSource: """
            protocol BatchProcessor {
                associatedtype Item = Int
                func process(items: [Item]) -> Int
            }

            #if DEBUG
            public class BatchProcessorMock: BatchProcessor {
                public typealias Item = Int
                public var processCallCount: Int = 0
                public var processCallArgs: [[Item]] = []
                public var processHandler: (@Sendable ([Item]) -> Int)? = nil
                public func process(items: [Item]) -> Int {
                    processCallCount += 1
                    processCallArgs.append(items)
                    guard let _handler = processHandler else {
                        fatalError("\\(Self.self).processHandler is not set")
                    }
                    return _handler(items)
                }
                public func resetMock() {
                    processCallCount = 0
                    processCallArgs = []
                    processHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with associated type and async throws method")
    func associatedTypeWithAsyncThrows() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol AsyncRepository {
                associatedtype Entity
                func fetch(id: String) async throws -> Entity
                func save(_ entity: Entity) async throws
            }
            """,
            expandedSource: """
            protocol AsyncRepository {
                associatedtype Entity
                func fetch(id: String) async throws -> Entity
                func save(_ entity: Entity) async throws
            }

            #if DEBUG
            public class AsyncRepositoryMock: AsyncRepository {
                public typealias Entity = Any
                public var fetchCallCount: Int = 0
                public var fetchCallArgs: [String] = []
                public var fetchHandler: (@Sendable (String) async throws -> Entity)? = nil
                public func fetch(id: String) async throws -> Entity {
                    fetchCallCount += 1
                    fetchCallArgs.append(id)
                    guard let _handler = fetchHandler else {
                        fatalError("\\(Self.self).fetchHandler is not set")
                    }
                    return try await _handler(id)
                }
                public var saveCallCount: Int = 0
                public var saveCallArgs: [Entity] = []
                public var saveHandler: (@Sendable (Entity) async throws -> Void)? = nil
                public func save(_ entity: Entity) async throws {
                    saveCallCount += 1
                    saveCallArgs.append(entity)
                    if let _handler = saveHandler {
                        try await _handler(entity)
                    }
                }
                public func resetMock() {
                    fetchCallCount = 0
                    fetchCallArgs = []
                    fetchHandler = nil
                    saveCallCount = 0
                    saveCallArgs = []
                    saveHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Sendable protocol with associated type without default")
    func sendableProtocolWithAssociatedTypeNoDefault() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol ThreadSafeCache: Sendable {
                associatedtype Key
                associatedtype Value
                func get(key: Key) -> Value?
            }
            """,
            expandedSource: """
            protocol ThreadSafeCache: Sendable {
                associatedtype Key
                associatedtype Value
                func get(key: Key) -> Value?
            }

            #if DEBUG
            #if canImport(Synchronization)
            @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
            public final class ThreadSafeCacheMock: ThreadSafeCache, Sendable {
                public typealias Key = Any
                public typealias Value = Any
                private struct Storage {
                    var getCallCount: Int = 0
                    var getCallArgs: [Key] = []
                    var getHandler: (@Sendable (Key) -> Value?)? = nil
                }
                private let _storage = Mutex<Storage>(Storage())
                public var getCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.getCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.getCallCount = newValue
                        }
                    }
                }
                public var getCallArgs: [Key] {
                    get {
                        _storage.withLock {
                            $0.getCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.getCallArgs = newValue
                        }
                    }
                }
                public var getHandler: (@Sendable (Key) -> Value?)? {
                    get {
                        _storage.withLock {
                            $0.getHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.getHandler = newValue
                        }
                    }
                }
                public func get(key: Key) -> Value? {
                    let _handler = _storage.withLock { storage -> (@Sendable (Key) -> Value?)? in
                        storage.getCallCount += 1
                        storage.getCallArgs.append(key)
                        return storage.getHandler
                    }
                    guard let _handler else {
                        fatalError("\\(Self.self).getHandler is not set")
                    }
                    return _handler(key)
                }
                public func resetMock() {
                    _storage.withLock { storage in
                        storage.getCallCount = 0
                        storage.getCallArgs = []
                        storage.getHandler = nil
                    }
                }
            }
            #else
            public final class ThreadSafeCacheMock: ThreadSafeCache, Sendable {
                public typealias Key = Any
                public typealias Value = Any
                private struct Storage {
                    var getCallCount: Int = 0
                    var getCallArgs: [Key] = []
                    var getHandler: (@Sendable (Key) -> Value?)? = nil
                }
                private let _storage = LegacyLock<Storage>(Storage())
                public var getCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.getCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.getCallCount = newValue
                        }
                    }
                }
                public var getCallArgs: [Key] {
                    get {
                        _storage.withLock {
                            $0.getCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.getCallArgs = newValue
                        }
                    }
                }
                public var getHandler: (@Sendable (Key) -> Value?)? {
                    get {
                        _storage.withLock {
                            $0.getHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.getHandler = newValue
                        }
                    }
                }
                public func get(key: Key) -> Value? {
                    let _handler = _storage.withLock { storage -> (@Sendable (Key) -> Value?)? in
                        storage.getCallCount += 1
                        storage.getCallArgs.append(key)
                        return storage.getHandler
                    }
                    guard let _handler else {
                        fatalError("\\(Self.self).getHandler is not set")
                    }
                    return _handler(key)
                }
                public func resetMock() {
                    _storage.withLock { storage in
                        storage.getCallCount = 0
                        storage.getCallArgs = []
                        storage.getHandler = nil
                    }
                }
            }
            #endif
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with associated type and closure parameter")
    func associatedTypeWithClosure() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol EventEmitter {
                associatedtype Event = String
                func subscribe(handler: @escaping (Event) -> Void)
            }
            """,
            expandedSource: """
            protocol EventEmitter {
                associatedtype Event = String
                func subscribe(handler: @escaping (Event) -> Void)
            }

            #if DEBUG
            public class EventEmitterMock: EventEmitter {
                public typealias Event = String
                public var subscribeCallCount: Int = 0
                public var subscribeCallArgs: [(Event) -> Void] = []
                public var subscribeHandler: (@Sendable ((Event) -> Void) -> Void)? = nil
                public func subscribe(handler: @escaping (Event) -> Void) {
                    subscribeCallCount += 1
                    subscribeCallArgs.append(handler)
                    if let _handler = subscribeHandler {
                        _handler(handler)
                    }
                }
                public func resetMock() {
                    subscribeCallCount = 0
                    subscribeCallArgs = []
                    subscribeHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }
}
