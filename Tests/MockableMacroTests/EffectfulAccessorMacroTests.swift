import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import MockableMacros

@Suite("Effectful Accessor Macro Tests")
struct EffectfulAccessorMacroTests {
    private let testMacros: [String: Macro.Type] = [
        "Mockable": MockableMacro.self
    ]

    @Test("get async throws property generates a handler-based mock")
    func asyncThrowsGetterGeneratesHandlerBasedMock() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol TokenProvider {
                var token: String { get async throws }
            }
            """,
            expandedSource: """
            protocol TokenProvider {
                var token: String { get async throws }
            }

            #if DEBUG
            class TokenProviderMock: TokenProvider {
                var tokenCallCount: Int = 0
                var tokenHandler: (@Sendable () async throws -> String)? = nil
                var token: String {
                    get async throws {
                        tokenCallCount += 1
                        guard let _handler = tokenHandler else {
                            fatalError("\\(Self.self).tokenHandler is not set")
                        }
                        return try await _handler()
                    }
                }
                func resetMock() {
                    tokenCallCount = 0
                    tokenHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("get throws property generates a throwing handler")
    func throwingGetterGeneratesThrowingHandler() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol ConfigProvider {
                var maxRetryCount: Int { get throws }
            }
            """,
            expandedSource: """
            protocol ConfigProvider {
                var maxRetryCount: Int { get throws }
            }

            #if DEBUG
            class ConfigProviderMock: ConfigProvider {
                var maxRetryCountCallCount: Int = 0
                var maxRetryCountHandler: (@Sendable () throws -> Int)? = nil
                var maxRetryCount: Int {
                    get throws {
                        maxRetryCountCallCount += 1
                        guard let _handler = maxRetryCountHandler else {
                            fatalError("\\(Self.self).maxRetryCountHandler is not set")
                        }
                        return try _handler()
                    }
                }
                func resetMock() {
                    maxRetryCountCallCount = 0
                    maxRetryCountHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("optional get async property returns nil when the handler is unset")
    func optionalAsyncGetterReturnsNilWithoutHandler() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol CacheProvider {
                var cachedValue: String? { get async }
            }
            """,
            expandedSource: """
            protocol CacheProvider {
                var cachedValue: String? { get async }
            }

            #if DEBUG
            class CacheProviderMock: CacheProvider {
                var cachedValueCallCount: Int = 0
                var cachedValueHandler: (@Sendable () async -> String?)? = nil
                var cachedValue: String? {
                    get async {
                        cachedValueCallCount += 1
                        guard let _handler = cachedValueHandler else {
                            return nil
                        }
                        return await _handler()
                    }
                }
                func resetMock() {
                    cachedValueCallCount = 0
                    cachedValueHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Sendable protocol stores the effectful property handler behind the lock")
    func sendableProtocolUsesLockBasedHandlerStorage() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol RemoteConfig: Sendable {
                var flag: Bool { get async throws }
            }
            """,
            expandedSource: """
            protocol RemoteConfig: Sendable {
                var flag: Bool { get async throws }
            }

            #if DEBUG
            class RemoteConfigMock: RemoteConfig, @unchecked Sendable {
                private struct Storage {
                    var flagCallCount: Int = 0
                    var flagHandler: (@Sendable () async throws -> Bool)? = nil
                }
                private let _storage = MockableLock<Storage>(Storage())
                var flagCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.flagCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.flagCallCount = newValue
                        }
                    }
                }
                var flagHandler: (@Sendable () async throws -> Bool)? {
                    get {
                        _storage.withLock {
                            $0.flagHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.flagHandler = newValue
                        }
                    }
                }
                var flag: Bool {
                    get async throws {
                        let _handler = _storage.withLock { storage -> (@Sendable () async throws -> Bool)? in
                            storage.flagCallCount += 1
                            return storage.flagHandler
                        }
                        guard let _handler else {
                            fatalError("\\(Self.self).flagHandler is not set")
                        }
                        return try await _handler()
                    }
                }
                func resetMock() {
                    _storage.withLock { storage in
                        storage.flagCallCount = 0
                        storage.flagHandler = nil
                    }
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("actor mock keeps the effectful property witness actor-isolated")
    func actorProtocolKeepsWitnessIsolated() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol TokenStore: Actor {
                var token: String { get async throws }
            }
            """,
            expandedSource: """
            protocol TokenStore: Actor {
                var token: String { get async throws }
            }

            #if DEBUG
            actor TokenStoreMock: TokenStore {
                private struct Storage {
                    var tokenCallCount: Int = 0
                    var tokenHandler: (@Sendable () async throws -> String)? = nil
                }
                private let _storage = MockableLock<Storage>(Storage())
                nonisolated var tokenCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.tokenCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.tokenCallCount = newValue
                        }
                    }
                }
                nonisolated var tokenHandler: (@Sendable () async throws -> String)? {
                    get {
                        _storage.withLock {
                            $0.tokenHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.tokenHandler = newValue
                        }
                    }
                }
                var token: String {
                    get async throws {
                        let _handler = _storage.withLock { storage -> (@Sendable () async throws -> String)? in
                            storage.tokenCallCount += 1
                            return storage.tokenHandler
                        }
                        guard let _handler else {
                            fatalError("\\(Self.self).tokenHandler is not set")
                        }
                        return try await _handler()
                    }
                }
                nonisolated func resetMock() {
                    _storage.withLock { storage in
                        storage.tokenCallCount = 0
                        storage.tokenHandler = nil
                    }
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("static effectful property uses the static storage lock")
    func staticEffectfulPropertyUsesStaticStorage() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol KeyProvider {
                static var apiKey: String { get throws }
            }
            """,
            expandedSource: """
            protocol KeyProvider {
                static var apiKey: String { get throws }
            }

            #if DEBUG
            class KeyProviderMock: KeyProvider {
                private struct StaticStorage {
                    var apiKeyCallCount: Int = 0
                    var apiKeyHandler: (@Sendable () throws -> String)? = nil
                }
                private static let _staticStorage = MockableLock<StaticStorage>(StaticStorage())
                static var apiKeyCallCount: Int {
                    get {
                        _staticStorage.withLock {
                            $0.apiKeyCallCount
                        }
                    }
                    set {
                        _staticStorage.withLock {
                            $0.apiKeyCallCount = newValue
                        }
                    }
                }
                static var apiKeyHandler: (@Sendable () throws -> String)? {
                    get {
                        _staticStorage.withLock {
                            $0.apiKeyHandler
                        }
                    }
                    set {
                        _staticStorage.withLock {
                            $0.apiKeyHandler = newValue
                        }
                    }
                }
                static var apiKey: String {
                    get throws {
                        let _handler = _staticStorage.withLock { storage -> (@Sendable () throws -> String)? in
                            storage.apiKeyCallCount += 1
                            return storage.apiKeyHandler
                        }
                        guard let _handler else {
                            fatalError("\\(Self.self).apiKeyHandler is not set")
                        }
                        return try _handler()
                    }
                }
                func resetMock() {
                    Self.apiKeyCallCount = 0
                    Self.apiKeyHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }
}
