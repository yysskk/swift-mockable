import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import MockableMacros

@Suite("MainActor Macro Tests")
struct MainActorMacroTests {
    private let testMacros: [String: Macro.Type] = [
        "Mockable": MockableMacro.self
    ]

    @Test("@MainActor protocol generates @MainActor mock class")
    func mainActorProtocol() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            @MainActor
            protocol Presenter {
                func loadData()
                var title: String { get }
            }
            """,
            expandedSource: """
            @MainActor
            protocol Presenter {
                func loadData()
                var title: String { get }
            }

            #if DEBUG
            @MainActor class PresenterMock: Presenter {
                private(set) var loadDataCallCount: Int = 0
                @available(*, deprecated, message: "loadData records no arguments; use loadDataCallCount instead.")
                var loadDataCallArguments: [()] {
                    Array(repeating: (), count: loadDataCallCount)
                }
                var loadDataHandler: (@Sendable () -> Void)? = nil
                func loadData() {
                    loadDataCallCount += 1
                    if let _handler = loadDataHandler {
                        _handler()
                    }
                }
                private var _title: String? = nil
                var title: String {
                    get {
                        _title!
                    }
                    set {
                        _title = newValue
                    }
                }
                func resetMock() {
                    loadDataCallCount = 0
                    loadDataHandler = nil
                    _title = nil
                }
                class func resetStaticMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("@MainActor protocol with async method")
    func mainActorProtocolWithAsyncMethod() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            @MainActor
            protocol AsyncPresenter {
                func fetchItems() async -> [String]
            }
            """,
            expandedSource: """
            @MainActor
            protocol AsyncPresenter {
                func fetchItems() async -> [String]
            }

            #if DEBUG
            @MainActor class AsyncPresenterMock: AsyncPresenter {
                private(set) var fetchItemsCallCount: Int = 0
                @available(*, deprecated, message: "fetchItems records no arguments; use fetchItemsCallCount instead.")
                var fetchItemsCallArguments: [()] {
                    Array(repeating: (), count: fetchItemsCallCount)
                }
                var fetchItemsHandler: (@Sendable () async -> [String])? = nil
                func fetchItems() async -> [String] {
                    fetchItemsCallCount += 1
                    guard let _handler = fetchItemsHandler else {
                        return []
                    }
                    return await _handler()
                }
                func resetMock() {
                    fetchItemsCallCount = 0
                    fetchItemsHandler = nil
                }
                class func resetStaticMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("A nonisolated requirement gets nonisolated, lock-backed tracking members")
    func nonisolatedRequirement() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            @MainActor
            protocol Presenter {
                nonisolated var id: String { get }
                nonisolated func track(_ event: String)
            }
            """,
            expandedSource: """
            @MainActor
            protocol Presenter {
                nonisolated var id: String { get }
                nonisolated func track(_ event: String)
            }

            #if DEBUG
            @MainActor class PresenterMock: Presenter {
                private struct Storage {
                    var _id: String? = nil
                    var trackCallCount: Int = 0
                    var trackCallArguments: [String] = []
                    var trackHandler: (@Sendable (String) -> Void)? = nil
                }
                private nonisolated let _storage = _MockableLock<Storage>(Storage())
                nonisolated var id: String {
                    get {
                        _storage.withLock {
                            $0._id!
                        }
                    }
                    set {
                        _storage.withLock {
                            $0._id = newValue
                        }
                    }
                }
                nonisolated var trackCallCount: Int {
                    _storage.withLock {
                        $0.trackCallCount
                    }
                }
                nonisolated var trackCallArguments: [String] {
                    _storage.withLock {
                        $0.trackCallArguments
                    }
                }
                nonisolated var trackHandler: (@Sendable (String) -> Void)? {
                    get {
                        _storage.withLock {
                            $0.trackHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.trackHandler = newValue
                        }
                    }
                }
                func track(_ event: String) {
                    let _handler = _storage.withLock { storage -> (@Sendable (String) -> Void)? in
                        storage.trackCallCount += 1
                        storage.trackCallArguments.append(event)
                        return storage.trackHandler
                    }
                    if let _handler {
                        _handler(event)
                    }
                }
                nonisolated func resetMock() {
                    _storage.withLock { storage in
                        storage._id = nil
                        storage.trackCallCount = 0
                        storage.trackCallArguments = []
                        storage.trackHandler = nil
                    }
                }
                nonisolated class func resetStaticMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("A @MainActor child of another protocol keeps its state behind a nonisolated lock")
    func childOfParentProtocol() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            @MainActor
            protocol Child: Base {
                func load()
                static func make() -> Int
            }
            """,
            expandedSource: """
            @MainActor
            protocol Child: Base {
                func load()
                static func make() -> Int
            }

            #if DEBUG
            @MainActor class ChildMock: BaseMock, Child {
                private struct Storage {
                    var loadCallCount: Int = 0
                    var loadHandler: (@Sendable () -> Void)? = nil
                }
                private nonisolated let _storage = _MockableLock<Storage>(Storage())
                private struct StaticStorage {
                    var makeCallCount: Int = 0
                    var makeHandler: (@Sendable () -> Int)? = nil
                }
                private static nonisolated let _staticStorage = _MockableLock<StaticStorage>(StaticStorage())
                var loadCallCount: Int {
                    _storage.withLock {
                        $0.loadCallCount
                    }
                }
                @available(*, deprecated, message: "load records no arguments; use loadCallCount instead.")
                var loadCallArguments: [()] {
                    Array(repeating: (), count: loadCallCount)
                }
                var loadHandler: (@Sendable () -> Void)? {
                    get {
                        _storage.withLock {
                            $0.loadHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.loadHandler = newValue
                        }
                    }
                }
                func load() {
                    let _handler = _storage.withLock { storage -> (@Sendable () -> Void)? in
                        storage.loadCallCount += 1
                        return storage.loadHandler
                    }
                    if let _handler {
                        _handler()
                    }
                }
                static var makeCallCount: Int {
                    _staticStorage.withLock {
                        $0.makeCallCount
                    }
                }
                @available(*, deprecated, message: "make records no arguments; use makeCallCount instead.")
                static var makeCallArguments: [()] {
                    Array(repeating: (), count: makeCallCount)
                }
                static var makeHandler: (@Sendable () -> Int)? {
                    get {
                        _staticStorage.withLock {
                            $0.makeHandler
                        }
                    }
                    set {
                        _staticStorage.withLock {
                            $0.makeHandler = newValue
                        }
                    }
                }
                static func make() -> Int {
                    let _handler = _staticStorage.withLock { storage -> (@Sendable () -> Int)? in
                        storage.makeCallCount += 1
                        return storage.makeHandler
                    }
                    guard let _handler else {
                        fatalError("\\(Self.self).makeHandler is not set")
                    }
                    return _handler()
                }
                override func resetMock() {
                    super.resetMock()
                    _storage.withLock { storage in
                        storage.loadCallCount = 0
                        storage.loadHandler = nil
                    }
                }
                override class func resetStaticMock() {
                    super.resetStaticMock()
                    Self._staticStorage.withLock { storage in
                        storage.makeCallCount = 0
                        storage.makeHandler = nil
                    }
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("A nonisolated requirement of a @MainActor child leaves the resetMock override unmarked")
    func nonisolatedRequirementOfChild() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            @MainActor
            protocol Child: Base {
                nonisolated func track()
            }
            """,
            expandedSource: """
            @MainActor
            protocol Child: Base {
                nonisolated func track()
            }

            #if DEBUG
            @MainActor class ChildMock: BaseMock, Child {
                private struct Storage {
                    var trackCallCount: Int = 0
                    var trackHandler: (@Sendable () -> Void)? = nil
                }
                private nonisolated let _storage = _MockableLock<Storage>(Storage())
                nonisolated var trackCallCount: Int {
                    _storage.withLock {
                        $0.trackCallCount
                    }
                }
                @available(*, deprecated, message: "track records no arguments; use trackCallCount instead.")
                nonisolated var trackCallArguments: [()] {
                    Array(repeating: (), count: trackCallCount)
                }
                nonisolated var trackHandler: (@Sendable () -> Void)? {
                    get {
                        _storage.withLock {
                            $0.trackHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.trackHandler = newValue
                        }
                    }
                }
                func track() {
                    let _handler = _storage.withLock { storage -> (@Sendable () -> Void)? in
                        storage.trackCallCount += 1
                        return storage.trackHandler
                    }
                    if let _handler {
                        _handler()
                    }
                }
                override func resetMock() {
                    super.resetMock()
                    _storage.withLock { storage in
                        storage.trackCallCount = 0
                        storage.trackHandler = nil
                    }
                }
                override class func resetStaticMock() {
                    super.resetStaticMock()
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("A requirement with an isolated parameter gets nonisolated, lock-backed tracking members")
    func isolatedParameterRequirement() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            @MainActor
            protocol Runner {
                func run(on actor: isolated any Actor) async
                func load()
            }
            """,
            expandedSource: """
            @MainActor
            protocol Runner {
                func run(on actor: isolated any Actor) async
                func load()
            }

            #if DEBUG
            @MainActor class RunnerMock: Runner {
                private struct Storage {
                    var runCallCount: Int = 0
                    var runCallArguments: [any Actor] = []
                    var runHandler: (@Sendable (any Actor) async -> Void)? = nil
                    var loadCallCount: Int = 0
                    var loadHandler: (@Sendable () -> Void)? = nil
                }
                private nonisolated let _storage = _MockableLock<Storage>(Storage())
                nonisolated var runCallCount: Int {
                    _storage.withLock {
                        $0.runCallCount
                    }
                }
                nonisolated var runCallArguments: [any Actor] {
                    _storage.withLock {
                        $0.runCallArguments
                    }
                }
                nonisolated var runHandler: (@Sendable (any Actor) async -> Void)? {
                    get {
                        _storage.withLock {
                            $0.runHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.runHandler = newValue
                        }
                    }
                }
                func run(on actor: isolated any Actor) async {
                    let _handler = _storage.withLock { storage -> (@Sendable (any Actor) async -> Void)? in
                        storage.runCallCount += 1
                        storage.runCallArguments.append(actor)
                        return storage.runHandler
                    }
                    if let _handler {
                        await _handler(actor)
                    }
                }
                var loadCallCount: Int {
                    _storage.withLock {
                        $0.loadCallCount
                    }
                }
                @available(*, deprecated, message: "load records no arguments; use loadCallCount instead.")
                var loadCallArguments: [()] {
                    Array(repeating: (), count: loadCallCount)
                }
                var loadHandler: (@Sendable () -> Void)? {
                    get {
                        _storage.withLock {
                            $0.loadHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.loadHandler = newValue
                        }
                    }
                }
                func load() {
                    let _handler = _storage.withLock { storage -> (@Sendable () -> Void)? in
                        storage.loadCallCount += 1
                        return storage.loadHandler
                    }
                    if let _handler {
                        _handler()
                    }
                }
                nonisolated func resetMock() {
                    _storage.withLock { storage in
                        storage.runCallCount = 0
                        storage.runCallArguments = []
                        storage.runHandler = nil
                        storage.loadCallCount = 0
                        storage.loadHandler = nil
                    }
                }
                nonisolated class func resetStaticMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }
}
