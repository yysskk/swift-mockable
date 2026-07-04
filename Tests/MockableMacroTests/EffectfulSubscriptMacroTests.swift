import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import MockableMacros

@Suite("Effectful Subscript Macro Tests")
struct EffectfulSubscriptMacroTests {
    private let testMacros: [String: Macro.Type] = [
        "Mockable": MockableMacro.self
    ]

    @Test("get async throws subscript generates an effectful handler-based accessor")
    func asyncThrowsSubscriptGeneratesEffectfulAccessor() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Store {
                subscript(key: String) -> Int { get async throws }
            }
            """,
            expandedSource: """
            protocol Store {
                subscript(key: String) -> Int { get async throws }
            }

            #if DEBUG
            class StoreMock: Store {
                var subscriptStringCallCount: Int = 0
                var subscriptStringCallArgs: [String] = []
                var subscriptStringHandler: (@Sendable (String) async throws -> Int )? = nil
                subscript(key: String) -> Int {
                    get async throws {
                        subscriptStringCallCount += 1
                        subscriptStringCallArgs.append(key)
                        guard let _handler = subscriptStringHandler else {
                            fatalError("\\(Self.self).subscriptStringHandler is not set")
                        }
                        return try await _handler(key)
                    }
                }
                func resetMock() {
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

    @Test("get throws subscript emits a try prefix without await")
    func throwingSubscriptEmitsTryWithoutAwait() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Store {
                subscript(key: String) -> Int { get throws }
            }
            """,
            expandedSource: """
            protocol Store {
                subscript(key: String) -> Int { get throws }
            }

            #if DEBUG
            class StoreMock: Store {
                var subscriptStringCallCount: Int = 0
                var subscriptStringCallArgs: [String] = []
                var subscriptStringHandler: (@Sendable (String) throws -> Int )? = nil
                subscript(key: String) -> Int {
                    get throws {
                        subscriptStringCallCount += 1
                        subscriptStringCallArgs.append(key)
                        guard let _handler = subscriptStringHandler else {
                            fatalError("\\(Self.self).subscriptStringHandler is not set")
                        }
                        return try _handler(key)
                    }
                }
                func resetMock() {
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

    @Test("Sendable protocol stores the effectful subscript handler behind the lock")
    func sendableProtocolUsesLockBasedEffectfulSubscript() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol RemoteStore: Sendable {
                subscript(key: String) -> Int { get async throws }
            }
            """,
            expandedSource: """
            protocol RemoteStore: Sendable {
                subscript(key: String) -> Int { get async throws }
            }

            #if DEBUG
            class RemoteStoreMock: RemoteStore, @unchecked Sendable {
                private struct Storage {
                    var subscriptStringCallCount: Int = 0
                    var subscriptStringCallArgs: [String] = []
                    var subscriptStringHandler: (@Sendable (String) async throws -> Int )? = nil
                }
                private let _storage = MockableLock<Storage>(Storage())
                var subscriptStringCallCount: Int {
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
                var subscriptStringCallArgs: [String] {
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
                var subscriptStringHandler: (@Sendable (String) async throws -> Int )? {
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
                subscript(key: String) -> Int {
                    get async throws {
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
                        return try await _handler(key)
                    }
                }
                func resetMock() {
                    _storage.withLock { storage in
                        storage.subscriptStringCallCount = 0
                        storage.subscriptStringCallArgs = []
                        storage.subscriptStringHandler = nil
                    }
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }
}
