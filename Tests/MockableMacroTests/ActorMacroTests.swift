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
            #if canImport(Synchronization)
            @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
            actor UserProfileStoreMock: UserProfileStore {
                private struct Storage {
                    var _profiles: [String: String]? = nil
                    var updateProfileCallCount: Int = 0
                    var updateProfileCallArgs: [(profile: String, key: String)] = []
                    var updateProfileHandler: (@Sendable ((profile: String, key: String)) -> Void)? = nil
                    var profileCallCount: Int = 0
                    var profileCallArgs: [String] = []
                    var profileHandler: (@Sendable (String) -> String?)? = nil
                    var resetCallCount: Int = 0
                    var resetCallArgs: [()] = []
                    var resetHandler: (@Sendable () -> Void)? = nil
                }
                private let _storage = Mutex<Storage>(Storage())
                nonisolated var _profiles: [String: String]? {
                    get {
                        _storage.withLock {
                            $0._profiles
                        }
                    }
                    set {
                        _storage.withLock {
                            $0._profiles = newValue
                        }
                    }
                }
                var profiles: [String: String] {
                    _storage.withLock {
                        $0._profiles!
                    }
                }
                nonisolated var updateProfileCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.updateProfileCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.updateProfileCallCount = newValue
                        }
                    }
                }
                nonisolated var updateProfileCallArgs: [(profile: String, key: String)] {
                    get {
                        _storage.withLock {
                            $0.updateProfileCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.updateProfileCallArgs = newValue
                        }
                    }
                }
                nonisolated var updateProfileHandler: (@Sendable ((profile: String, key: String)) -> Void)? {
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
                    let _handler = _storage.withLock { storage -> (@Sendable ((profile: String, key: String)) -> Void)? in
                        storage.updateProfileCallCount += 1
                        storage.updateProfileCallArgs.append((profile: profile, key: key))
                        return storage.updateProfileHandler
                    }
                    if let _handler {
                        _handler((profile: profile, key: key))
                    }
                }
                nonisolated var profileCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.profileCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.profileCallCount = newValue
                        }
                    }
                }
                nonisolated var profileCallArgs: [String] {
                    get {
                        _storage.withLock {
                            $0.profileCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.profileCallArgs = newValue
                        }
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
                        storage.profileCallArgs.append(key)
                        return storage.profileHandler
                    }
                    guard let _handler else {
                        fatalError("\\(Self.self).profileHandler is not set")
                    }
                    return _handler(key)
                }
                nonisolated var resetCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.resetCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.resetCallCount = newValue
                        }
                    }
                }
                nonisolated var resetCallArgs: [()] {
                    get {
                        _storage.withLock {
                            $0.resetCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.resetCallArgs = newValue
                        }
                    }
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
                        storage.resetCallArgs.append(())
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
                        storage.updateProfileCallArgs = []
                        storage.updateProfileHandler = nil
                        storage.profileCallCount = 0
                        storage.profileCallArgs = []
                        storage.profileHandler = nil
                        storage.resetCallCount = 0
                        storage.resetCallArgs = []
                        storage.resetHandler = nil
                    }
                }
            }
            #else
            actor UserProfileStoreMock: UserProfileStore {
                private struct Storage {
                    var _profiles: [String: String]? = nil
                    var updateProfileCallCount: Int = 0
                    var updateProfileCallArgs: [(profile: String, key: String)] = []
                    var updateProfileHandler: (@Sendable ((profile: String, key: String)) -> Void)? = nil
                    var profileCallCount: Int = 0
                    var profileCallArgs: [String] = []
                    var profileHandler: (@Sendable (String) -> String?)? = nil
                    var resetCallCount: Int = 0
                    var resetCallArgs: [()] = []
                    var resetHandler: (@Sendable () -> Void)? = nil
                }
                private let _storage = LegacyLock<Storage>(Storage())
                nonisolated var _profiles: [String: String]? {
                    get {
                        _storage.withLock {
                            $0._profiles
                        }
                    }
                    set {
                        _storage.withLock {
                            $0._profiles = newValue
                        }
                    }
                }
                var profiles: [String: String] {
                    _storage.withLock {
                        $0._profiles!
                    }
                }
                nonisolated var updateProfileCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.updateProfileCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.updateProfileCallCount = newValue
                        }
                    }
                }
                nonisolated var updateProfileCallArgs: [(profile: String, key: String)] {
                    get {
                        _storage.withLock {
                            $0.updateProfileCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.updateProfileCallArgs = newValue
                        }
                    }
                }
                nonisolated var updateProfileHandler: (@Sendable ((profile: String, key: String)) -> Void)? {
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
                    let _handler = _storage.withLock { storage -> (@Sendable ((profile: String, key: String)) -> Void)? in
                        storage.updateProfileCallCount += 1
                        storage.updateProfileCallArgs.append((profile: profile, key: key))
                        return storage.updateProfileHandler
                    }
                    if let _handler {
                        _handler((profile: profile, key: key))
                    }
                }
                nonisolated var profileCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.profileCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.profileCallCount = newValue
                        }
                    }
                }
                nonisolated var profileCallArgs: [String] {
                    get {
                        _storage.withLock {
                            $0.profileCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.profileCallArgs = newValue
                        }
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
                        storage.profileCallArgs.append(key)
                        return storage.profileHandler
                    }
                    guard let _handler else {
                        fatalError("\\(Self.self).profileHandler is not set")
                    }
                    return _handler(key)
                }
                nonisolated var resetCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.resetCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.resetCallCount = newValue
                        }
                    }
                }
                nonisolated var resetCallArgs: [()] {
                    get {
                        _storage.withLock {
                            $0.resetCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.resetCallArgs = newValue
                        }
                    }
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
                        storage.resetCallArgs.append(())
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
                        storage.updateProfileCallArgs = []
                        storage.updateProfileHandler = nil
                        storage.profileCallCount = 0
                        storage.profileCallArgs = []
                        storage.profileHandler = nil
                        storage.resetCallCount = 0
                        storage.resetCallArgs = []
                        storage.resetHandler = nil
                    }
                }
            }
            #endif
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
            #if canImport(Synchronization)
            @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
            actor ConfigProviderMock: ConfigProvider {
                private struct Storage {
                    var _apiKey: String? = nil
                    var _timeout: Int? = nil
                }
                private let _storage = Mutex<Storage>(Storage())
                nonisolated var _apiKey: String? {
                    get {
                        _storage.withLock {
                            $0._apiKey
                        }
                    }
                    set {
                        _storage.withLock {
                            $0._apiKey = newValue
                        }
                    }
                }
                var apiKey: String {
                    _storage.withLock {
                        $0._apiKey!
                    }
                }
                nonisolated var _timeout: Int? {
                    get {
                        _storage.withLock {
                            $0._timeout
                        }
                    }
                    set {
                        _storage.withLock {
                            $0._timeout = newValue
                        }
                    }
                }
                var timeout: Int {
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
            }
            #else
            actor ConfigProviderMock: ConfigProvider {
                private struct Storage {
                    var _apiKey: String? = nil
                    var _timeout: Int? = nil
                }
                private let _storage = LegacyLock<Storage>(Storage())
                nonisolated var _apiKey: String? {
                    get {
                        _storage.withLock {
                            $0._apiKey
                        }
                    }
                    set {
                        _storage.withLock {
                            $0._apiKey = newValue
                        }
                    }
                }
                var apiKey: String {
                    _storage.withLock {
                        $0._apiKey!
                    }
                }
                nonisolated var _timeout: Int? {
                    get {
                        _storage.withLock {
                            $0._timeout
                        }
                    }
                    set {
                        _storage.withLock {
                            $0._timeout = newValue
                        }
                    }
                }
                var timeout: Int {
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
            }
            #endif
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
            #if canImport(Synchronization)
            @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
            actor DataStoreMock: DataStore {
                private struct Storage {
                    var saveCallCount: Int = 0
                    var saveCallArgs: [String] = []
                    var saveHandler: (@Sendable (String) async throws -> Void)? = nil
                    var loadCallCount: Int = 0
                    var loadCallArgs: [()] = []
                    var loadHandler: (@Sendable () async throws -> String)? = nil
                }
                private let _storage = Mutex<Storage>(Storage())
                nonisolated var saveCallCount: Int {
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
                nonisolated var saveCallArgs: [String] {
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
                        storage.saveCallArgs.append(data)
                        return storage.saveHandler
                    }
                    if let _handler {
                        try await _handler(data)
                    }
                }
                nonisolated var loadCallCount: Int {
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
                nonisolated var loadCallArgs: [()] {
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
                        storage.loadCallArgs.append(())
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
                        storage.saveCallArgs = []
                        storage.saveHandler = nil
                        storage.loadCallCount = 0
                        storage.loadCallArgs = []
                        storage.loadHandler = nil
                    }
                }
            }
            #else
            actor DataStoreMock: DataStore {
                private struct Storage {
                    var saveCallCount: Int = 0
                    var saveCallArgs: [String] = []
                    var saveHandler: (@Sendable (String) async throws -> Void)? = nil
                    var loadCallCount: Int = 0
                    var loadCallArgs: [()] = []
                    var loadHandler: (@Sendable () async throws -> String)? = nil
                }
                private let _storage = LegacyLock<Storage>(Storage())
                nonisolated var saveCallCount: Int {
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
                nonisolated var saveCallArgs: [String] {
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
                        storage.saveCallArgs.append(data)
                        return storage.saveHandler
                    }
                    if let _handler {
                        try await _handler(data)
                    }
                }
                nonisolated var loadCallCount: Int {
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
                nonisolated var loadCallArgs: [()] {
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
                        storage.loadCallArgs.append(())
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
                        storage.saveCallArgs = []
                        storage.saveHandler = nil
                        storage.loadCallCount = 0
                        storage.loadCallArgs = []
                        storage.loadHandler = nil
                    }
                }
            }
            #endif
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Actor protocol with legacyLock: true uses LegacyLock only")
    func actorProtocolWithForceLegacyLock() {
        assertMacroExpansionForTesting(
            """
            @Mockable(legacyLock: true)
            protocol ConfigProvider: Actor {
                var apiKey: String { get }
            }
            """,
            expandedSource: """
            protocol ConfigProvider: Actor {
                var apiKey: String { get }
            }

            #if DEBUG
            actor ConfigProviderMock: ConfigProvider {
                private struct Storage {
                    var _apiKey: String? = nil
                }
                private let _storage = LegacyLock<Storage>(Storage())
                nonisolated var _apiKey: String? {
                    get {
                        _storage.withLock {
                            $0._apiKey
                        }
                    }
                    set {
                        _storage.withLock {
                            $0._apiKey = newValue
                        }
                    }
                }
                var apiKey: String {
                    _storage.withLock {
                        $0._apiKey!
                    }
                }
                nonisolated func resetMock() {
                    _storage.withLock { storage in
                        storage._apiKey = nil
                    }
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }
}
