import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import MockableMacros

@Suite("Actor Macro Tests")
struct ActorMacroTests {
    private let testMacros: [String: Macro.Type] = [
        "Mockable": MockableMacro.self
    ]

    @Test("Actor protocol generates actor mock")
    func actorProtocol() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol UserProfileStore: Actor {
                var profiles: [String: String] { get }
                func updateProfile(_ profile: String, for key: String)
                func profile(for key: String) -> String?
                func reset()
            }
            """,
            expandedSource: """
            protocol UserProfileStore: Actor {
                var profiles: [String: String] { get }
                func updateProfile(_ profile: String, for key: String)
                func profile(for key: String) -> String?
                func reset()
            }

            #if DEBUG
            actor UserProfileStoreMock: UserProfileStore {
                private struct Storage {
                    var _profiles: [String: String]? = nil
                    var updateProfileCallCount: Int = 0
                    var updateProfileCallArguments: [(profile: String, key: String)] = []
                    var updateProfileHandler: (@Sendable (String, String) -> Void)? = nil
                    var profileCallCount: Int = 0
                    var profileCallArguments: [String] = []
                    var profileHandler: (@Sendable (String) -> String?)? = nil
                    var resetCallCount: Int = 0
                    var resetHandler: (@Sendable () -> Void)? = nil
                }
                private let _storage = MockableLock<Storage>(Storage())
                nonisolated var profiles: [String: String] {
                    get {
                        _storage.withLock {
                            $0._profiles!
                        }
                    }
                    set {
                        _storage.withLock {
                            $0._profiles = newValue
                        }
                    }
                }
                nonisolated var updateProfileCallCount: Int {
                    _storage.withLock {
                        $0.updateProfileCallCount
                    }
                }
                nonisolated var updateProfileCallArguments: [(profile: String, key: String)] {
                    _storage.withLock {
                        $0.updateProfileCallArguments
                    }
                }
                nonisolated var updateProfileHandler: (@Sendable (String, String) -> Void)? {
                    get {
                        _storage.withLock {
                            $0.updateProfileHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.updateProfileHandler = newValue
                        }
                    }
                }
                func updateProfile(_ profile: String, for key: String) {
                    let _handler = _storage.withLock { storage -> (@Sendable (String, String) -> Void)? in
                        storage.updateProfileCallCount += 1
                        storage.updateProfileCallArguments.append((profile: profile, key: key))
                        return storage.updateProfileHandler
                    }
                    if let _handler {
                        _handler(profile, key)
                    }
                }
                nonisolated var profileCallCount: Int {
                    _storage.withLock {
                        $0.profileCallCount
                    }
                }
                nonisolated var profileCallArguments: [String] {
                    _storage.withLock {
                        $0.profileCallArguments
                    }
                }
                nonisolated var profileHandler: (@Sendable (String) -> String?)? {
                    get {
                        _storage.withLock {
                            $0.profileHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.profileHandler = newValue
                        }
                    }
                }
                func profile(for key: String) -> String? {
                    let _handler = _storage.withLock { storage -> (@Sendable (String) -> String?)? in
                        storage.profileCallCount += 1
                        storage.profileCallArguments.append(key)
                        return storage.profileHandler
                    }
                    guard let _handler else {
                        return nil
                    }
                    return _handler(key)
                }
                nonisolated var resetCallCount: Int {
                    _storage.withLock {
                        $0.resetCallCount
                    }
                }
                @available(*, deprecated, message: "reset records no arguments; use resetCallCount instead.")
                nonisolated var resetCallArguments: [()] {
                    Array(repeating: (), count: resetCallCount)
                }
                nonisolated var resetHandler: (@Sendable () -> Void)? {
                    get {
                        _storage.withLock {
                            $0.resetHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.resetHandler = newValue
                        }
                    }
                }
                func reset() {
                    let _handler = _storage.withLock { storage -> (@Sendable () -> Void)? in
                        storage.resetCallCount += 1
                        return storage.resetHandler
                    }
                    if let _handler {
                        _handler()
                    }
                }
                nonisolated func resetMock() {
                    _storage.withLock { storage in
                        storage._profiles = nil
                        storage.updateProfileCallCount = 0
                        storage.updateProfileCallArguments = []
                        storage.updateProfileHandler = nil
                        storage.profileCallCount = 0
                        storage.profileCallArguments = []
                        storage.profileHandler = nil
                        storage.resetCallCount = 0
                        storage.resetHandler = nil
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

    @Test("Actor protocol with property")
    func actorProtocolWithProperty() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol ConfigProvider: Actor {
                var apiKey: String { get }
                var timeout: Int { get set }
            }
            """,
            expandedSource: """
            protocol ConfigProvider: Actor {
                var apiKey: String { get }
                var timeout: Int { get set }
            }

            #if DEBUG
            actor ConfigProviderMock: ConfigProvider {
                private struct Storage {
                    var _apiKey: String? = nil
                    var _timeout: Int? = nil
                }
                private let _storage = MockableLock<Storage>(Storage())
                nonisolated var apiKey: String {
                    get {
                        _storage.withLock {
                            $0._apiKey!
                        }
                    }
                    set {
                        _storage.withLock {
                            $0._apiKey = newValue
                        }
                    }
                }
                nonisolated var timeout: Int {
                    get {
                        _storage.withLock {
                            $0._timeout!
                        }
                    }
                    set {
                        _storage.withLock {
                            $0._timeout = newValue
                        }
                    }
                }
                nonisolated func resetMock() {
                    _storage.withLock { storage in
                        storage._apiKey = nil
                        storage._timeout = nil
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

    @Test("Actor protocol with async throws method")
    func actorProtocolWithAsyncThrows() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol DataStore: Actor {
                func save(_ data: String) async throws
                func load() async throws -> String
            }
            """,
            expandedSource: """
            protocol DataStore: Actor {
                func save(_ data: String) async throws
                func load() async throws -> String
            }

            #if DEBUG
            actor DataStoreMock: DataStore {
                private struct Storage {
                    var saveCallCount: Int = 0
                    var saveCallArguments: [String] = []
                    var saveHandler: (@Sendable (String) async throws -> Void)? = nil
                    var loadCallCount: Int = 0
                    var loadHandler: (@Sendable () async throws -> String)? = nil
                }
                private let _storage = MockableLock<Storage>(Storage())
                nonisolated var saveCallCount: Int {
                    _storage.withLock {
                        $0.saveCallCount
                    }
                }
                nonisolated var saveCallArguments: [String] {
                    _storage.withLock {
                        $0.saveCallArguments
                    }
                }
                nonisolated var saveHandler: (@Sendable (String) async throws -> Void)? {
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
                func save(_ data: String) async throws {
                    let _handler = _storage.withLock { storage -> (@Sendable (String) async throws -> Void)? in
                        storage.saveCallCount += 1
                        storage.saveCallArguments.append(data)
                        return storage.saveHandler
                    }
                    if let _handler {
                        try await _handler(data)
                    }
                }
                nonisolated var loadCallCount: Int {
                    _storage.withLock {
                        $0.loadCallCount
                    }
                }
                @available(*, deprecated, message: "load records no arguments; use loadCallCount instead.")
                nonisolated var loadCallArguments: [()] {
                    Array(repeating: (), count: loadCallCount)
                }
                nonisolated var loadHandler: (@Sendable () async throws -> String)? {
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
                func load() async throws -> String {
                    let _handler = _storage.withLock { storage -> (@Sendable () async throws -> String)? in
                        storage.loadCallCount += 1
                        return storage.loadHandler
                    }
                    guard let _handler else {
                        fatalError("\\(Self.self).loadHandler is not set")
                    }
                    return try await _handler()
                }
                nonisolated func resetMock() {
                    _storage.withLock { storage in
                        storage.saveCallCount = 0
                        storage.saveCallArguments = []
                        storage.saveHandler = nil
                        storage.loadCallCount = 0
                        storage.loadHandler = nil
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

}
