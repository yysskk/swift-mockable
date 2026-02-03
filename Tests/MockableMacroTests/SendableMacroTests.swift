import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import MockableMacros

@Suite("Sendable Macro Tests")
struct SendableMacroTests {
    private let testMacros: [String: Macro.Type] = [
        "Mockable": MockableMacro.self
    ]

    @Test("Sendable protocol generates thread-safe mock with Mutex")
    func sendableProtocol() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            public protocol KeychainClientProtocol: Sendable {
                func save(_ data: Data, forKey key: String) throws
                func load(forKey key: String) throws -> Data?
                func delete(forKey key: String) throws
                func exists(forKey key: String) -> Bool
            }
            """,
            expandedSource: """
            public protocol KeychainClientProtocol: Sendable {
                func save(_ data: Data, forKey key: String) throws
                func load(forKey key: String) throws -> Data?
                func delete(forKey key: String) throws
                func exists(forKey key: String) -> Bool
            }

            #if DEBUG
            #if canImport(Synchronization)
            @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
            public final class KeychainClientProtocolMock: KeychainClientProtocol, Sendable {
                private struct Storage {
                    var saveCallCount: Int = 0
                    var saveCallArgs: [(data: Data, key: String)] = []
                    var saveHandler: (@Sendable ((data: Data, key: String)) throws -> Void)? = nil
                    var loadCallCount: Int = 0
                    var loadCallArgs: [String] = []
                    var loadHandler: (@Sendable (String) throws -> Data?)? = nil
                    var deleteCallCount: Int = 0
                    var deleteCallArgs: [String] = []
                    var deleteHandler: (@Sendable (String) throws -> Void)? = nil
                    var existsCallCount: Int = 0
                    var existsCallArgs: [String] = []
                    var existsHandler: (@Sendable (String) -> Bool)? = nil
                }
                private let _storage = Mutex<Storage>(Storage())
                public var saveCallCount: Int {
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
                public var saveCallArgs: [(data: Data, key: String)] {
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
                public var saveHandler: (@Sendable ((data: Data, key: String)) throws -> Void)? {
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
                public func save(_ data: Data, forKey key: String) throws {
                    let _handler = _storage.withLock { storage -> (@Sendable ((data: Data, key: String)) throws -> Void)? in
                        storage.saveCallCount += 1
                        storage.saveCallArgs.append((data: data, key: key))
                        return storage.saveHandler
                    }
                    if let _handler {
                        try _handler((data: data, key: key))
                    }
                }
                public var loadCallCount: Int {
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
                public var loadCallArgs: [String] {
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
                public var loadHandler: (@Sendable (String) throws -> Data?)? {
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
                public func load(forKey key: String) throws -> Data? {
                    let _handler = _storage.withLock { storage -> (@Sendable (String) throws -> Data?)? in
                        storage.loadCallCount += 1
                        storage.loadCallArgs.append(key)
                        return storage.loadHandler
                    }
                    guard let _handler else {
                        fatalError("\\(Self.self).loadHandler is not set")
                    }
                    return try _handler(key)
                }
                public var deleteCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.deleteCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.deleteCallCount = newValue
                        }
                    }
                }
                public var deleteCallArgs: [String] {
                    get {
                        _storage.withLock {
                            $0.deleteCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.deleteCallArgs = newValue
                        }
                    }
                }
                public var deleteHandler: (@Sendable (String) throws -> Void)? {
                    get {
                        _storage.withLock {
                            $0.deleteHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.deleteHandler = newValue
                        }
                    }
                }
                public func delete(forKey key: String) throws {
                    let _handler = _storage.withLock { storage -> (@Sendable (String) throws -> Void)? in
                        storage.deleteCallCount += 1
                        storage.deleteCallArgs.append(key)
                        return storage.deleteHandler
                    }
                    if let _handler {
                        try _handler(key)
                    }
                }
                public var existsCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.existsCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.existsCallCount = newValue
                        }
                    }
                }
                public var existsCallArgs: [String] {
                    get {
                        _storage.withLock {
                            $0.existsCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.existsCallArgs = newValue
                        }
                    }
                }
                public var existsHandler: (@Sendable (String) -> Bool)? {
                    get {
                        _storage.withLock {
                            $0.existsHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.existsHandler = newValue
                        }
                    }
                }
                public func exists(forKey key: String) -> Bool {
                    let _handler = _storage.withLock { storage -> (@Sendable (String) -> Bool)? in
                        storage.existsCallCount += 1
                        storage.existsCallArgs.append(key)
                        return storage.existsHandler
                    }
                    guard let _handler else {
                        fatalError("\\(Self.self).existsHandler is not set")
                    }
                    return _handler(key)
                }
                public func resetMock() {
                    _storage.withLock { storage in
                        storage.saveCallCount = 0
                        storage.saveCallArgs = []
                        storage.saveHandler = nil
                        storage.loadCallCount = 0
                        storage.loadCallArgs = []
                        storage.loadHandler = nil
                        storage.deleteCallCount = 0
                        storage.deleteCallArgs = []
                        storage.deleteHandler = nil
                        storage.existsCallCount = 0
                        storage.existsCallArgs = []
                        storage.existsHandler = nil
                    }
                }
            }
            #else
            public final class KeychainClientProtocolMock: KeychainClientProtocol, Sendable {
                private struct Storage {
                    var saveCallCount: Int = 0
                    var saveCallArgs: [(data: Data, key: String)] = []
                    var saveHandler: (@Sendable ((data: Data, key: String)) throws -> Void)? = nil
                    var loadCallCount: Int = 0
                    var loadCallArgs: [String] = []
                    var loadHandler: (@Sendable (String) throws -> Data?)? = nil
                    var deleteCallCount: Int = 0
                    var deleteCallArgs: [String] = []
                    var deleteHandler: (@Sendable (String) throws -> Void)? = nil
                    var existsCallCount: Int = 0
                    var existsCallArgs: [String] = []
                    var existsHandler: (@Sendable (String) -> Bool)? = nil
                }
                private let _storage = LegacyLock<Storage>(Storage())
                public var saveCallCount: Int {
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
                public var saveCallArgs: [(data: Data, key: String)] {
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
                public var saveHandler: (@Sendable ((data: Data, key: String)) throws -> Void)? {
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
                public func save(_ data: Data, forKey key: String) throws {
                    let _handler = _storage.withLock { storage -> (@Sendable ((data: Data, key: String)) throws -> Void)? in
                        storage.saveCallCount += 1
                        storage.saveCallArgs.append((data: data, key: key))
                        return storage.saveHandler
                    }
                    if let _handler {
                        try _handler((data: data, key: key))
                    }
                }
                public var loadCallCount: Int {
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
                public var loadCallArgs: [String] {
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
                public var loadHandler: (@Sendable (String) throws -> Data?)? {
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
                public func load(forKey key: String) throws -> Data? {
                    let _handler = _storage.withLock { storage -> (@Sendable (String) throws -> Data?)? in
                        storage.loadCallCount += 1
                        storage.loadCallArgs.append(key)
                        return storage.loadHandler
                    }
                    guard let _handler else {
                        fatalError("\\(Self.self).loadHandler is not set")
                    }
                    return try _handler(key)
                }
                public var deleteCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.deleteCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.deleteCallCount = newValue
                        }
                    }
                }
                public var deleteCallArgs: [String] {
                    get {
                        _storage.withLock {
                            $0.deleteCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.deleteCallArgs = newValue
                        }
                    }
                }
                public var deleteHandler: (@Sendable (String) throws -> Void)? {
                    get {
                        _storage.withLock {
                            $0.deleteHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.deleteHandler = newValue
                        }
                    }
                }
                public func delete(forKey key: String) throws {
                    let _handler = _storage.withLock { storage -> (@Sendable (String) throws -> Void)? in
                        storage.deleteCallCount += 1
                        storage.deleteCallArgs.append(key)
                        return storage.deleteHandler
                    }
                    if let _handler {
                        try _handler(key)
                    }
                }
                public var existsCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.existsCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.existsCallCount = newValue
                        }
                    }
                }
                public var existsCallArgs: [String] {
                    get {
                        _storage.withLock {
                            $0.existsCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.existsCallArgs = newValue
                        }
                    }
                }
                public var existsHandler: (@Sendable (String) -> Bool)? {
                    get {
                        _storage.withLock {
                            $0.existsHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.existsHandler = newValue
                        }
                    }
                }
                public func exists(forKey key: String) -> Bool {
                    let _handler = _storage.withLock { storage -> (@Sendable (String) -> Bool)? in
                        storage.existsCallCount += 1
                        storage.existsCallArgs.append(key)
                        return storage.existsHandler
                    }
                    guard let _handler else {
                        fatalError("\\(Self.self).existsHandler is not set")
                    }
                    return _handler(key)
                }
                public func resetMock() {
                    _storage.withLock { storage in
                        storage.saveCallCount = 0
                        storage.saveCallArgs = []
                        storage.saveHandler = nil
                        storage.loadCallCount = 0
                        storage.loadCallArgs = []
                        storage.loadHandler = nil
                        storage.deleteCallCount = 0
                        storage.deleteCallArgs = []
                        storage.deleteHandler = nil
                        storage.existsCallCount = 0
                        storage.existsCallArgs = []
                        storage.existsHandler = nil
                    }
                }
            }
            #endif
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Sendable protocol with @Sendable attribute")
    func sendableProtocolWithAttribute() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            @Sendable
            protocol Logger {
                func log(message: String)
            }
            """,
            expandedSource: """
            @Sendable
            protocol Logger {
                func log(message: String)
            }

            #if DEBUG
            #if canImport(Synchronization)
            @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
            final class LoggerMock: Logger, Sendable {
                private struct Storage {
                    var logCallCount: Int = 0
                    var logCallArgs: [String] = []
                    var logHandler: (@Sendable (String) -> Void)? = nil
                }
                private let _storage = Mutex<Storage>(Storage())
                var logCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.logCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.logCallCount = newValue
                        }
                    }
                }
                var logCallArgs: [String] {
                    get {
                        _storage.withLock {
                            $0.logCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.logCallArgs = newValue
                        }
                    }
                }
                var logHandler: (@Sendable (String) -> Void)? {
                    get {
                        _storage.withLock {
                            $0.logHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.logHandler = newValue
                        }
                    }
                }
                func log(message: String) {
                    let _handler = _storage.withLock { storage -> (@Sendable (String) -> Void)? in
                        storage.logCallCount += 1
                        storage.logCallArgs.append(message)
                        return storage.logHandler
                    }
                    if let _handler {
                        _handler(message)
                    }
                }
                func resetMock() {
                    _storage.withLock { storage in
                        storage.logCallCount = 0
                        storage.logCallArgs = []
                        storage.logHandler = nil
                    }
                }
            }
            #else
            final class LoggerMock: Logger, Sendable {
                private struct Storage {
                    var logCallCount: Int = 0
                    var logCallArgs: [String] = []
                    var logHandler: (@Sendable (String) -> Void)? = nil
                }
                private let _storage = LegacyLock<Storage>(Storage())
                var logCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.logCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.logCallCount = newValue
                        }
                    }
                }
                var logCallArgs: [String] {
                    get {
                        _storage.withLock {
                            $0.logCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.logCallArgs = newValue
                        }
                    }
                }
                var logHandler: (@Sendable (String) -> Void)? {
                    get {
                        _storage.withLock {
                            $0.logHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.logHandler = newValue
                        }
                    }
                }
                func log(message: String) {
                    let _handler = _storage.withLock { storage -> (@Sendable (String) -> Void)? in
                        storage.logCallCount += 1
                        storage.logCallArgs.append(message)
                        return storage.logHandler
                    }
                    if let _handler {
                        _handler(message)
                    }
                }
                func resetMock() {
                    _storage.withLock { storage in
                        storage.logCallCount = 0
                        storage.logCallArgs = []
                        storage.logHandler = nil
                    }
                }
            }
            #endif
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Sendable protocol with @escaping @Sendable closure parameter")
    func sendableProtocolWithEscapingClosure() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol EventService: Sendable {
                func register(handler: @escaping @Sendable (String) -> Void) async
            }
            """,
            expandedSource: """
            protocol EventService: Sendable {
                func register(handler: @escaping @Sendable (String) -> Void) async
            }

            #if DEBUG
            #if canImport(Synchronization)
            @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
            final class EventServiceMock: EventService, Sendable {
                private struct Storage {
                    var registerCallCount: Int = 0
                    var registerCallArgs: [@Sendable (String) -> Void] = []
                    var registerHandler: (@Sendable (@Sendable (String) -> Void) async -> Void)? = nil
                }
                private let _storage = Mutex<Storage>(Storage())
                var registerCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.registerCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.registerCallCount = newValue
                        }
                    }
                }
                var registerCallArgs: [@Sendable (String) -> Void] {
                    get {
                        _storage.withLock {
                            $0.registerCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.registerCallArgs = newValue
                        }
                    }
                }
                var registerHandler: (@Sendable (@Sendable (String) -> Void) async -> Void)? {
                    get {
                        _storage.withLock {
                            $0.registerHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.registerHandler = newValue
                        }
                    }
                }
                func register(handler: @escaping @Sendable (String) -> Void) async {
                    let _handler = _storage.withLock { storage -> (@Sendable (@Sendable (String) -> Void) async -> Void)? in
                        storage.registerCallCount += 1
                        storage.registerCallArgs.append(handler)
                        return storage.registerHandler
                    }
                    if let _handler {
                        await _handler(handler)
                    }
                }
                func resetMock() {
                    _storage.withLock { storage in
                        storage.registerCallCount = 0
                        storage.registerCallArgs = []
                        storage.registerHandler = nil
                    }
                }
            }
            #else
            final class EventServiceMock: EventService, Sendable {
                private struct Storage {
                    var registerCallCount: Int = 0
                    var registerCallArgs: [@Sendable (String) -> Void] = []
                    var registerHandler: (@Sendable (@Sendable (String) -> Void) async -> Void)? = nil
                }
                private let _storage = LegacyLock<Storage>(Storage())
                var registerCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.registerCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.registerCallCount = newValue
                        }
                    }
                }
                var registerCallArgs: [@Sendable (String) -> Void] {
                    get {
                        _storage.withLock {
                            $0.registerCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.registerCallArgs = newValue
                        }
                    }
                }
                var registerHandler: (@Sendable (@Sendable (String) -> Void) async -> Void)? {
                    get {
                        _storage.withLock {
                            $0.registerHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.registerHandler = newValue
                        }
                    }
                }
                func register(handler: @escaping @Sendable (String) -> Void) async {
                    let _handler = _storage.withLock { storage -> (@Sendable (@Sendable (String) -> Void) async -> Void)? in
                        storage.registerCallCount += 1
                        storage.registerCallArgs.append(handler)
                        return storage.registerHandler
                    }
                    if let _handler {
                        await _handler(handler)
                    }
                }
                func resetMock() {
                    _storage.withLock { storage in
                        storage.registerCallCount = 0
                        storage.registerCallArgs = []
                        storage.registerHandler = nil
                    }
                }
            }
            #endif
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Sendable protocol with property")
    func sendableProtocolWithProperty() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol ConfigProvider: Sendable {
                var apiKey: String { get }
                var timeout: Int { get set }
            }
            """,
            expandedSource: """
            protocol ConfigProvider: Sendable {
                var apiKey: String { get }
                var timeout: Int { get set }
            }

            #if DEBUG
            #if canImport(Synchronization)
            @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
            final class ConfigProviderMock: ConfigProvider, Sendable {
                private struct Storage {
                    var _apiKey: String? = nil
                    var _timeout: Int? = nil
                }
                private let _storage = Mutex<Storage>(Storage())
                var _apiKey: String? {
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
                func resetMock() {
                    _storage.withLock { storage in
                        storage._apiKey = nil
                        storage._timeout = nil
                    }
                }
            }
            #else
            final class ConfigProviderMock: ConfigProvider, Sendable {
                private struct Storage {
                    var _apiKey: String? = nil
                    var _timeout: Int? = nil
                }
                private let _storage = LegacyLock<Storage>(Storage())
                var _apiKey: String? {
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
                func resetMock() {
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
}
