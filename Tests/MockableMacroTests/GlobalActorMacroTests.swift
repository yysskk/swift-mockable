import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import MockableMacros

@Suite("Global Actor Macro Tests")
struct GlobalActorMacroTests {
    private let testMacros: [String: Macro.Type] = [
        "Mockable": MockableMacro.self
    ]

    @Test("A custom global actor isolates the mock and frees its nonisolated requirement")
    func customGlobalActor() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            @DataActor
            protocol Store {
                nonisolated var id: String { get }
                func save(_ value: String)
            }
            """,
            expandedSource: """
            @DataActor
            protocol Store {
                nonisolated var id: String { get }
                func save(_ value: String)
            }

            #if DEBUG
            @DataActor class StoreMock: Store {
                private struct Storage {
                    var _id: String? = nil
                    var saveCallCount: Int = 0
                    var saveCallArguments: [String] = []
                    var saveHandler: (@Sendable (String) -> Void)? = nil
                }
                private nonisolated let _storage = MockableLock<Storage>(Storage())
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
                var saveCallCount: Int {
                    _storage.withLock {
                        $0.saveCallCount
                    }
                }
                var saveCallArguments: [String] {
                    _storage.withLock {
                        $0.saveCallArguments
                    }
                }
                var saveHandler: (@Sendable (String) -> Void)? {
                    get {
                        _storage.withLock {
                            $0.saveHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.saveHandler = newValue
                        }
                    }
                }
                func save(_ value: String) {
                    let _handler = _storage.withLock { storage -> (@Sendable (String) -> Void)? in
                        storage.saveCallCount += 1
                        storage.saveCallArguments.append(value)
                        return storage.saveHandler
                    }
                    if let _handler {
                        _handler(value)
                    }
                }
                nonisolated func resetMock() {
                    _storage.withLock { storage in
                        storage._id = nil
                        storage.saveCallCount = 0
                        storage.saveCallArguments = []
                        storage.saveHandler = nil
                    }
                }
                nonisolated class func resetMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("A module-qualified global actor is carried onto the mock as written")
    func qualifiedGlobalActor() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            @Persistence.DataActor
            protocol Store {
                func save()
            }
            """,
            expandedSource: """
            @Persistence.DataActor
            protocol Store {
                func save()
            }

            #if DEBUG
            @Persistence.DataActor class StoreMock: Store {
                private(set) var saveCallCount: Int = 0
                @available(*, deprecated, message: "save records no arguments; use saveCallCount instead.")
                var saveCallArguments: [()] {
                    Array(repeating: (), count: saveCallCount)
                }
                var saveHandler: (@Sendable () -> Void)? = nil
                func save() {
                    saveCallCount += 1
                    if let _handler = saveHandler {
                        _handler()
                    }
                }
                func resetMock() {
                    saveCallCount = 0
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

    @Test("A nonisolated requirement moves the state behind the lock even without an attribute")
    func nonisolatedRequirementWithoutAttribute() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Child: IsolatedBase {
                nonisolated func track()
            }
            """,
            expandedSource: """
            protocol Child: IsolatedBase {
                nonisolated func track()
            }

            #if DEBUG
            class ChildMock: IsolatedBaseMock, Child {
                private struct Storage {
                    var trackCallCount: Int = 0
                    var trackHandler: (@Sendable () -> Void)? = nil
                }
                private nonisolated let _storage = MockableLock<Storage>(Storage())
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
                override class func resetMock() {
                    super.resetMock()
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }
}
