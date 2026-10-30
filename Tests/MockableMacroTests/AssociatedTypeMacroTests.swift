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
            class DataStoreMock: DataStore {
                typealias Model = Any
                private(set) var fetchCallCount: Int = 0
                private(set) var fetchCallArguments: [()] = []
                var fetchHandler: (() -> Model)? = nil
                func fetch() -> Model {
                    fetchCallCount += 1
                    fetchCallArguments.append(())
                    guard let _handler = fetchHandler else {
                        fatalError("\\(Self.self).fetchHandler is not set")
                    }
                    return _handler()
                }
                private(set) var saveCallCount: Int = 0
                private(set) var saveCallArguments: [Model] = []
                var saveHandler: ((Model) -> Void)? = nil
                func save(_ model: Model) {
                    saveCallCount += 1
                    saveCallArguments.append(model)
                    if let _handler = saveHandler {
                        _handler(model)
                    }
                }
                func resetMock() {
                    fetchCallCount = 0
                    fetchCallArguments = []
                    fetchHandler = nil
                    saveCallCount = 0
                    saveCallArguments = []
                    saveHandler = nil
                }
                class func resetMock() {
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
            class StringStoreMock: StringStore {
                typealias Element = String
                private(set) var getCallCount: Int = 0
                private(set) var getCallArguments: [()] = []
                var getHandler: (() -> Element)? = nil
                func get() -> Element {
                    getCallCount += 1
                    getCallArguments.append(())
                    guard let _handler = getHandler else {
                        fatalError("\\(Self.self).getHandler is not set")
                    }
                    return _handler()
                }
                func resetMock() {
                    getCallCount = 0
                    getCallArguments = []
                    getHandler = nil
                }
                class func resetMock() {
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
            class RepositoryMock: Repository {
                typealias Entity = Any
                typealias ID = String
                private(set) var findCallCount: Int = 0
                private(set) var findCallArguments: [ID] = []
                var findHandler: ((ID) -> Entity?)? = nil
                func find(by id: ID) -> Entity? {
                    findCallCount += 1
                    findCallArguments.append(id)
                    guard let _handler = findHandler else {
                        return nil
                    }
                    return _handler(id)
                }
                private(set) var saveCallCount: Int = 0
                private(set) var saveCallArguments: [Entity] = []
                var saveHandler: ((Entity) -> ID)? = nil
                func save(_ entity: Entity) -> ID {
                    saveCallCount += 1
                    saveCallArguments.append(entity)
                    guard let _handler = saveHandler else {
                        fatalError("\\(Self.self).saveHandler is not set")
                    }
                    return _handler(entity)
                }
                func resetMock() {
                    findCallCount = 0
                    findCallArguments = []
                    findHandler = nil
                    saveCallCount = 0
                    saveCallArguments = []
                    saveHandler = nil
                }
                class func resetMock() {
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
            class AsyncStoreMock: AsyncStore, @unchecked Sendable {
                typealias Item = String
                private struct Storage {
                    var fetchCallCount: Int = 0
                    var fetchCallArguments: [()] = []
                    var fetchHandler: (@Sendable () async -> Item)? = nil
                }
                private let _storage = MockableLock<Storage>(Storage())
                var fetchCallCount: Int {
                    _storage.withLock {
                        $0.fetchCallCount
                    }
                }
                var fetchCallArguments: [()] {
                    _storage.withLock {
                        $0.fetchCallArguments
                    }
                }
                var fetchHandler: (@Sendable () async -> Item)? {
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
                func fetch() async -> Item {
                    let _handler = _storage.withLock { storage -> (@Sendable () async -> Item)? in
                        storage.fetchCallCount += 1
                        storage.fetchCallArguments.append(())
                        return storage.fetchHandler
                    }
                    guard let _handler else {
                        fatalError("\\(Self.self).fetchHandler is not set")
                    }
                    return await _handler()
                }
                func resetMock() {
                    _storage.withLock { storage in
                        storage.fetchCallCount = 0
                        storage.fetchCallArguments = []
                        storage.fetchHandler = nil
                    }
                }
                class func resetMock() {
                }
            }
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
            actor CacheActorMock: CacheActor {
                typealias Value = Data
                private struct Storage {
                    var getCallCount: Int = 0
                    var getCallArguments: [String] = []
                    var getHandler: (@Sendable (String) -> Value?)? = nil
                    var setCallCount: Int = 0
                    var setCallArguments: [(key: String, value: Value)] = []
                    var setHandler: (@Sendable (String, Value) -> Void)? = nil
                }
                private let _storage = MockableLock<Storage>(Storage())
                nonisolated var getCallCount: Int {
                    _storage.withLock {
                        $0.getCallCount
                    }
                }
                nonisolated var getCallArguments: [String] {
                    _storage.withLock {
                        $0.getCallArguments
                    }
                }
                nonisolated var getHandler: (@Sendable (String) -> Value?)? {
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
                func get(key: String) -> Value? {
                    let _handler = _storage.withLock { storage -> (@Sendable (String) -> Value?)? in
                        storage.getCallCount += 1
                        storage.getCallArguments.append(key)
                        return storage.getHandler
                    }
                    guard let _handler else {
                        return nil
                    }
                    return _handler(key)
                }
                nonisolated var setCallCount: Int {
                    _storage.withLock {
                        $0.setCallCount
                    }
                }
                nonisolated var setCallArguments: [(key: String, value: Value)] {
                    _storage.withLock {
                        $0.setCallArguments
                    }
                }
                nonisolated var setHandler: (@Sendable (String, Value) -> Void)? {
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
                func set(key: String, value: Value) {
                    let _handler = _storage.withLock { storage -> (@Sendable (String, Value) -> Void)? in
                        storage.setCallCount += 1
                        storage.setCallArguments.append((key: key, value: value))
                        return storage.setHandler
                    }
                    if let _handler {
                        _handler(key, value)
                    }
                }
                nonisolated func resetMock() {
                    _storage.withLock { storage in
                        storage.getCallCount = 0
                        storage.getCallArguments = []
                        storage.getHandler = nil
                        storage.setCallCount = 0
                        storage.setCallArguments = []
                        storage.setHandler = nil
                    }
                }
                static func resetMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("A constrained associated type with no default is reported")
    func associatedTypeWithConstraint() {
        // `Any` cannot satisfy the constraint, so the mock would not conform. The
        // requirement is reported instead, where the author can add a default.
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
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: """
                        Cannot mock associated type 'Item': the mock fulfills it with 'Any', \
                        which does not satisfy its constraints. Give it a default \
                        ('associatedtype Item: ... = SomeType') so the mock has a type to use.
                        """,
                    line: 3,
                    column: 5
                )
            ],
            macros: testMacros
        )
    }

    @Test("A constrained associated type with a default is mocked with that default")
    func constrainedAssociatedTypeWithDefault() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol DecodableStore {
                associatedtype Item: Decodable = Data
                func decode(from data: Data) -> Item
            }
            """,
            expandedSource: """
            protocol DecodableStore {
                associatedtype Item: Decodable = Data
                func decode(from data: Data) -> Item
            }

            #if DEBUG
            class DecodableStoreMock: DecodableStore {
                typealias Item = Data
                private(set) var decodeCallCount: Int = 0
                private(set) var decodeCallArguments: [Data] = []
                var decodeHandler: ((Data) -> Item)? = nil
                func decode(from data: Data) -> Item {
                    decodeCallCount += 1
                    decodeCallArguments.append(data)
                    guard let _handler = decodeHandler else {
                        fatalError("\\(Self.self).decodeHandler is not set")
                    }
                    return _handler(data)
                }
                func resetMock() {
                    decodeCallCount = 0
                    decodeCallArguments = []
                    decodeHandler = nil
                }
                class func resetMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("A generic type alias keeps its parameter and where clauses")
    func genericTypeAlias() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol AliasHost {
                typealias Pair<T> = (T, T)
                func make() -> Int
            }
            """,
            expandedSource: """
            protocol AliasHost {
                typealias Pair<T> = (T, T)
                func make() -> Int
            }

            #if DEBUG
            class AliasHostMock: AliasHost {
                typealias Pair<T> = (T, T)
                private(set) var makeCallCount: Int = 0
                private(set) var makeCallArguments: [()] = []
                var makeHandler: (() -> Int)? = nil
                func make() -> Int {
                    makeCallCount += 1
                    makeCallArguments.append(())
                    guard let _handler = makeHandler else {
                        fatalError("\\(Self.self).makeHandler is not set")
                    }
                    return _handler()
                }
                func resetMock() {
                    makeCallCount = 0
                    makeCallArguments = []
                    makeHandler = nil
                }
                class func resetMock() {
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
            class StateHolderMock: StateHolder {
                typealias State = String
                private var _currentState: State? = nil
                var currentState: State {
                    get {
                        _currentState!
                    }
                    set {
                        _currentState = newValue
                    }
                }
                var previousState: State? = nil
                func resetMock() {
                    _currentState = nil
                    previousState = nil
                }
                class func resetMock() {
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
            class ArrayStoreMock: ArrayStore {
                typealias Element = [String: Int]
                private(set) var getAllCallCount: Int = 0
                private(set) var getAllCallArguments: [()] = []
                var getAllHandler: (() -> Element)? = nil
                func getAll() -> Element {
                    getAllCallCount += 1
                    getAllCallArguments.append(())
                    guard let _handler = getAllHandler else {
                        fatalError("\\(Self.self).getAllHandler is not set")
                    }
                    return _handler()
                }
                func resetMock() {
                    getAllCallCount = 0
                    getAllCallArguments = []
                    getAllHandler = nil
                }
                class func resetMock() {
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
            class OptionalFetcherMock: OptionalFetcher {
                typealias Result = Any
                private(set) var fetchCallCount: Int = 0
                private(set) var fetchCallArguments: [String] = []
                var fetchHandler: ((String) -> Result?)? = nil
                func fetch(id: String) -> Result? {
                    fetchCallCount += 1
                    fetchCallArguments.append(id)
                    guard let _handler = fetchHandler else {
                        return nil
                    }
                    return _handler(id)
                }
                func resetMock() {
                    fetchCallCount = 0
                    fetchCallArguments = []
                    fetchHandler = nil
                }
                class func resetMock() {
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
            class BatchProcessorMock: BatchProcessor {
                typealias Item = Int
                private(set) var processCallCount: Int = 0
                private(set) var processCallArguments: [[Item]] = []
                var processHandler: (([Item]) -> Int)? = nil
                func process(items: [Item]) -> Int {
                    processCallCount += 1
                    processCallArguments.append(items)
                    guard let _handler = processHandler else {
                        fatalError("\\(Self.self).processHandler is not set")
                    }
                    return _handler(items)
                }
                func resetMock() {
                    processCallCount = 0
                    processCallArguments = []
                    processHandler = nil
                }
                class func resetMock() {
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
            class AsyncRepositoryMock: AsyncRepository {
                typealias Entity = Any
                private(set) var fetchCallCount: Int = 0
                private(set) var fetchCallArguments: [String] = []
                var fetchHandler: ((String) async throws -> Entity)? = nil
                func fetch(id: String) async throws -> Entity {
                    fetchCallCount += 1
                    fetchCallArguments.append(id)
                    guard let _handler = fetchHandler else {
                        fatalError("\\(Self.self).fetchHandler is not set")
                    }
                    return try await _handler(id)
                }
                private(set) var saveCallCount: Int = 0
                private(set) var saveCallArguments: [Entity] = []
                var saveHandler: ((Entity) async throws -> Void)? = nil
                func save(_ entity: Entity) async throws {
                    saveCallCount += 1
                    saveCallArguments.append(entity)
                    if let _handler = saveHandler {
                        try await _handler(entity)
                    }
                }
                func resetMock() {
                    fetchCallCount = 0
                    fetchCallArguments = []
                    fetchHandler = nil
                    saveCallCount = 0
                    saveCallArguments = []
                    saveHandler = nil
                }
                class func resetMock() {
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
            class ThreadSafeCacheMock: ThreadSafeCache, @unchecked Sendable {
                typealias Key = Any
                typealias Value = Any
                private struct Storage {
                    var getCallCount: Int = 0
                    var getCallArguments: [Key] = []
                    var getHandler: (@Sendable (Key) -> Value?)? = nil
                }
                private let _storage = MockableLock<Storage>(Storage())
                var getCallCount: Int {
                    _storage.withLock {
                        $0.getCallCount
                    }
                }
                var getCallArguments: [Key] {
                    _storage.withLock {
                        $0.getCallArguments
                    }
                }
                var getHandler: (@Sendable (Key) -> Value?)? {
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
                func get(key: Key) -> Value? {
                    let _handler = _storage.withLock { storage -> (@Sendable (Key) -> Value?)? in
                        storage.getCallCount += 1
                        storage.getCallArguments.append(key)
                        return storage.getHandler
                    }
                    guard let _handler else {
                        return nil
                    }
                    return _handler(key)
                }
                func resetMock() {
                    _storage.withLock { storage in
                        storage.getCallCount = 0
                        storage.getCallArguments = []
                        storage.getHandler = nil
                    }
                }
                class func resetMock() {
                }
            }
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
            class EventEmitterMock: EventEmitter {
                typealias Event = String
                private(set) var subscribeCallCount: Int = 0
                private(set) var subscribeCallArguments: [(Event) -> Void] = []
                var subscribeHandler: (((Event) -> Void) -> Void)? = nil
                func subscribe(handler: @escaping (Event) -> Void) {
                    subscribeCallCount += 1
                    subscribeCallArguments.append(handler)
                    if let _handler = subscribeHandler {
                        _handler(handler)
                    }
                }
                func resetMock() {
                    subscribeCallCount = 0
                    subscribeCallArguments = []
                    subscribeHandler = nil
                }
                class func resetMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }
}
