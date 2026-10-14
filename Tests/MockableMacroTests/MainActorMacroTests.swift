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
                var loadDataCallCount: Int = 0
                var loadDataCallArgs: [()] = []
                var loadDataHandler: (@Sendable () -> Void)? = nil
                func loadData() {
                    loadDataCallCount += 1
                    loadDataCallArgs.append(())
                    if let _handler = loadDataHandler {
                        _handler()
                    }
                }
                var _title: String? = nil
                var title: String {
                    _title!
                }
                func resetMock() {
                    loadDataCallCount = 0
                    loadDataCallArgs = []
                    loadDataHandler = nil
                    _title = nil
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
                var fetchItemsCallCount: Int = 0
                var fetchItemsCallArgs: [()] = []
                var fetchItemsHandler: (@Sendable () async -> [String])? = nil
                func fetchItems() async -> [String] {
                    fetchItemsCallCount += 1
                    fetchItemsCallArgs.append(())
                    guard let _handler = fetchItemsHandler else {
                        return []
                    }
                    return await _handler()
                }
                func resetMock() {
                    fetchItemsCallCount = 0
                    fetchItemsCallArgs = []
                    fetchItemsHandler = nil
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
                    var trackCallArgs: [String] = []
                    var trackHandler: (@Sendable (String) -> Void)? = nil
                }
                private nonisolated let _storage = MockableLock<Storage>(Storage())
                nonisolated var _id: String? {
                    get {
                        _storage.withLock {
                            $0._id
                        }
                    }
                    set {
                        _storage.withLock {
                            $0._id = newValue
                        }
                    }
                }
                var id: String {
                    _storage.withLock {
                        $0._id!
                    }
                }
                nonisolated var trackCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.trackCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.trackCallCount = newValue
                        }
                    }
                }
                nonisolated var trackCallArgs: [String] {
                    get {
                        _storage.withLock {
                            $0.trackCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.trackCallArgs = newValue
                        }
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
                        storage.trackCallArgs.append(event)
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
                        storage.trackCallArgs = []
                        storage.trackHandler = nil
                    }
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
                    var loadCallArgs: [()] = []
                    var loadHandler: (@Sendable () -> Void)? = nil
                }
                private nonisolated let _storage = MockableLock<Storage>(Storage())
                private struct StaticStorage {
                    var makeCallCount: Int = 0
                    var makeCallArgs: [()] = []
                    var makeHandler: (@Sendable () -> Int)? = nil
                }
                private static nonisolated let _staticStorage = MockableLock<StaticStorage>(StaticStorage())
                var loadCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.loadCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.loadCallCount = newValue
                        }
                    }
                }
                var loadCallArgs: [()] {
                    get {
                        _storage.withLock {
                            $0.loadCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.loadCallArgs = newValue
                        }
                    }
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
                        storage.loadCallArgs.append(())
                        return storage.loadHandler
                    }
                    if let _handler {
                        _handler()
                    }
                }
                static var makeCallCount: Int {
                    get {
                        _staticStorage.withLock {
                            $0.makeCallCount
                        }
                    }
                    set {
                        _staticStorage.withLock {
                            $0.makeCallCount = newValue
                        }
                    }
                }
                static var makeCallArgs: [()] {
                    get {
                        _staticStorage.withLock {
                            $0.makeCallArgs
                        }
                    }
                    set {
                        _staticStorage.withLock {
                            $0.makeCallArgs = newValue
                        }
                    }
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
                        storage.makeCallArgs.append(())
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
                        storage.loadCallArgs = []
                        storage.loadHandler = nil
                    }
                    Self._staticStorage.withLock { storage in
                        storage.makeCallCount = 0
                        storage.makeCallArgs = []
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
                    var trackCallArgs: [()] = []
                    var trackHandler: (@Sendable () -> Void)? = nil
                }
                private nonisolated let _storage = MockableLock<Storage>(Storage())
                nonisolated var trackCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.trackCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.trackCallCount = newValue
                        }
                    }
                }
                nonisolated var trackCallArgs: [()] {
                    get {
                        _storage.withLock {
                            $0.trackCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.trackCallArgs = newValue
                        }
                    }
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
                        storage.trackCallArgs.append(())
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
                        storage.trackCallArgs = []
                        storage.trackHandler = nil
                    }
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
                    var runCallArgs: [any Actor] = []
                    var runHandler: (@Sendable (any Actor) async -> Void)? = nil
                    var loadCallCount: Int = 0
                    var loadCallArgs: [()] = []
                    var loadHandler: (@Sendable () -> Void)? = nil
                }
                private nonisolated let _storage = MockableLock<Storage>(Storage())
                nonisolated var runCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.runCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.runCallCount = newValue
                        }
                    }
                }
                nonisolated var runCallArgs: [any Actor] {
                    get {
                        _storage.withLock {
                            $0.runCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.runCallArgs = newValue
                        }
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
                        storage.runCallArgs.append(actor)
                        return storage.runHandler
                    }
                    if let _handler {
                        await _handler(actor)
                    }
                }
                var loadCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.loadCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.loadCallCount = newValue
                        }
                    }
                }
                var loadCallArgs: [()] {
                    get {
                        _storage.withLock {
                            $0.loadCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.loadCallArgs = newValue
                        }
                    }
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
                        storage.loadCallArgs.append(())
                        return storage.loadHandler
                    }
                    if let _handler {
                        _handler()
                    }
                }
                nonisolated func resetMock() {
                    _storage.withLock { storage in
                        storage.runCallCount = 0
                        storage.runCallArgs = []
                        storage.runHandler = nil
                        storage.loadCallCount = 0
                        storage.loadCallArgs = []
                        storage.loadHandler = nil
                    }
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }
}
