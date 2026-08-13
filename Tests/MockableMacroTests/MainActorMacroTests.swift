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
}
