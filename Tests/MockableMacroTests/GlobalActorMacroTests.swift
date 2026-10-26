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
                    var saveCallArgs: [String] = []
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
                    get {
                        _storage.withLock {
                            $0.saveCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.saveCallCount = newValue
                        }
                    }
                }
                var saveCallArgs: [String] {
                    get {
                        _storage.withLock {
                            $0.saveCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.saveCallArgs = newValue
                        }
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
                        storage.saveCallArgs.append(value)
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
                        storage.saveCallArgs = []
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
                var saveCallCount: Int = 0
                var saveCallArgs: [()] = []
                var saveHandler: (@Sendable () -> Void)? = nil
                func save() {
                    saveCallCount += 1
                    saveCallArgs.append(())
                    if let _handler = saveHandler {
                        _handler()
                    }
                }
                func resetMock() {
                    saveCallCount = 0
                    saveCallArgs = []
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
