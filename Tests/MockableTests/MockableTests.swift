import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import MockableMacros

let testMacros: [String: Macro.Type] = [
    "Mockable": MockableMacro.self
]

@Suite("MockableMacro Tests")
struct MockableMacroTests {
    @Test("Simple protocol with single method")
    func simpleProtocolWithMethod() {
        assertMacroExpansion(
            """
            @Mockable
            protocol UserService {
                func fetchUser(id: Int) -> String
            }
            """,
            expandedSource: """
            protocol UserService {
                func fetchUser(id: Int) -> String
            }
            #if DEBUG

            public class UserServiceMock: UserService {
                public var fetchUserCallCount: Int = 0
                public var fetchUserCallArgs: [Int] = []
                public var fetchUserHandler: (@Sendable (Int) -> String)?
                public func fetchUser(id: Int) -> String {
                    fetchUserCallCount += 1
                    fetchUserCallArgs.append(id)
                    guard let _handler = fetchUserHandler else {
                        fatalError("\\(Self.self).fetchUserHandler is not set")
                    }
                    return _handler(id)
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with async throws method")
    func asyncThrowsMethod() {
        assertMacroExpansion(
            """
            @Mockable
            protocol DataService {
                func loadData(from url: String) async throws -> Data
            }
            """,
            expandedSource: """
            protocol DataService {
                func loadData(from url: String) async throws -> Data
            }
            #if DEBUG

            public class DataServiceMock: DataService {
                public var loadDataCallCount: Int = 0
                public var loadDataCallArgs: [String] = []
                public var loadDataHandler: (@Sendable (String) async throws -> Data)?
                public func loadData(from url: String) async throws -> Data {
                    loadDataCallCount += 1
                    loadDataCallArgs.append(url)
                    guard let _handler = loadDataHandler else {
                        fatalError("\\(Self.self).loadDataHandler is not set")
                    }
                    return try await _handler(url)
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with multiple parameters")
    func multipleParameters() {
        assertMacroExpansion(
            """
            @Mockable
            protocol Calculator {
                func add(a: Int, b: Int) -> Int
            }
            """,
            expandedSource: """
            protocol Calculator {
                func add(a: Int, b: Int) -> Int
            }
            #if DEBUG

            public class CalculatorMock: Calculator {
                public var addCallCount: Int = 0
                public var addCallArgs: [(a: Int, b: Int)] = []
                public var addHandler: (@Sendable ((a: Int, b: Int)) -> Int)?
                public func add(a: Int, b: Int) -> Int {
                    addCallCount += 1
                    addCallArgs.append((a: a, b: b))
                    guard let _handler = addHandler else {
                        fatalError("\\(Self.self).addHandler is not set")
                    }
                    return _handler((a: a, b: b))
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with void method")
    func voidMethod() {
        assertMacroExpansion(
            """
            @Mockable
            protocol Logger {
                func log(message: String)
            }
            """,
            expandedSource: """
            protocol Logger {
                func log(message: String)
            }
            #if DEBUG

            public class LoggerMock: Logger {
                public var logCallCount: Int = 0
                public var logCallArgs: [String] = []
                public var logHandler: (@Sendable (String) -> Void)?
                public func log(message: String) {
                    logCallCount += 1
                    logCallArgs.append(message)
                    if let _handler = logHandler {
                        _handler(message)
                    }
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with get-only property")
    func getOnlyProperty() {
        assertMacroExpansion(
            """
            @Mockable
            protocol UserProvider {
                var currentUser: String { get }
            }
            """,
            expandedSource: """
            protocol UserProvider {
                var currentUser: String { get }
            }
            #if DEBUG

            public class UserProviderMock: UserProvider {
                public var _currentUser: String?
                public var currentUser: String {
                    _currentUser!
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with get-set property")
    func getSetProperty() {
        assertMacroExpansion(
            """
            @Mockable
            protocol Settings {
                var theme: String { get set }
            }
            """,
            expandedSource: """
            protocol Settings {
                var theme: String { get set }
            }
            #if DEBUG

            public class SettingsMock: Settings {
                public var _theme: String? = nil
                public var theme: String {
                    get {
                        _theme!
                    }
                    set {
                        _theme = newValue
                    }
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with optional property")
    func optionalProperty() {
        assertMacroExpansion(
            """
            @Mockable
            protocol Cache {
                var lastValue: String? { get set }
            }
            """,
            expandedSource: """
            protocol Cache {
                var lastValue: String? { get set }
            }
            #if DEBUG

            public class CacheMock: Cache {
                public var lastValue: String? = nil
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Non-protocol declaration should fail")
    func nonProtocolFails() {
        assertMacroExpansion(
            """
            @Mockable
            class MyClass {}
            """,
            expandedSource: """
            class MyClass {}
            """,
            diagnostics: [
                DiagnosticSpec(message: "@Mockable can only be applied to protocols", line: 1, column: 1)
            ],
            macros: testMacros
        )
    }

    @Test("Protocol with generic method returning generic type")
    func genericMethodWithReturn() {
        assertMacroExpansion(
            """
            @Mockable
            protocol Cache {
                func get<T>(_ key: String) -> T
            }
            """,
            expandedSource: """
            protocol Cache {
                func get<T>(_ key: String) -> T
            }
            #if DEBUG

            public class CacheMock: Cache {
                public var getCallCount: Int = 0
                public var getCallArgs: [String] = []
                public var getHandler: (@Sendable (String) -> Any)?
                public func get<T>(_ key: String) -> T {
                    getCallCount += 1
                    getCallArgs.append(key)
                    guard let _handler = getHandler else {
                        fatalError("\\(Self.self).getHandler is not set")
                    }
                    return _handler(key) as! T
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with generic method with generic parameter type")
    func genericMethodWithGenericParameter() {
        assertMacroExpansion(
            """
            @Mockable
            protocol Storage {
                func save<T>(_ value: T, forKey key: String)
            }
            """,
            expandedSource: """
            protocol Storage {
                func save<T>(_ value: T, forKey key: String)
            }
            #if DEBUG

            public class StorageMock: Storage {
                public var saveCallCount: Int = 0
                public var saveCallArgs: [(value: Any, key: String)] = []
                public var saveHandler: (@Sendable ((value: Any, key: String)) -> Void)?
                public func save<T>(_ value: T, forKey key: String) {
                    saveCallCount += 1
                    saveCallArgs.append((value: value, key: key))
                    if let _handler = saveHandler {
                        _handler((value: value, key: key))
                    }
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with generic method using wrapper type like UserDefaultsKey<T>")
    func genericMethodWithWrapperType() {
        assertMacroExpansion(
            """
            @Mockable
            protocol UserDefaultsClient {
                func get<T>(_ key: UserDefaultsKey<T>) -> T
                func set<T>(_ value: T, forKey key: UserDefaultsKey<T>)
            }
            """,
            expandedSource: """
            protocol UserDefaultsClient {
                func get<T>(_ key: UserDefaultsKey<T>) -> T
                func set<T>(_ value: T, forKey key: UserDefaultsKey<T>)
            }
            #if DEBUG

            public class UserDefaultsClientMock: UserDefaultsClient {
                public var getCallCount: Int = 0
                public var getCallArgs: [Any] = []
                public var getHandler: (@Sendable (Any) -> Any)?
                public func get<T>(_ key: UserDefaultsKey<T>) -> T {
                    getCallCount += 1
                    getCallArgs.append(key)
                    guard let _handler = getHandler else {
                        fatalError("\\(Self.self).getHandler is not set")
                    }
                    return _handler(key) as! T
                }
                public var setCallCount: Int = 0
                public var setCallArgs: [(value: Any, key: Any)] = []
                public var setHandler: (@Sendable ((value: Any, key: Any)) -> Void)?
                public func set<T>(_ value: T, forKey key: UserDefaultsKey<T>) {
                    setCallCount += 1
                    setCallArgs.append((value: value, key: key))
                    if let _handler = setHandler {
                        _handler((value: value, key: key))
                    }
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with concrete generic type parameters (non-generic method)")
    func concreteGenericTypeParameters() {
        assertMacroExpansion(
            """
            @Mockable
            protocol UserDefaultsClient {
                func integer(forKey key: UserDefaultsKey<Int>) -> Int
                func setInteger(_ value: Int, forKey key: UserDefaultsKey<Int>)
            }
            """,
            expandedSource: """
            protocol UserDefaultsClient {
                func integer(forKey key: UserDefaultsKey<Int>) -> Int
                func setInteger(_ value: Int, forKey key: UserDefaultsKey<Int>)
            }
            #if DEBUG

            public class UserDefaultsClientMock: UserDefaultsClient {
                public var integerCallCount: Int = 0
                public var integerCallArgs: [UserDefaultsKey<Int>] = []
                public var integerHandler: (@Sendable (UserDefaultsKey<Int>) -> Int)?
                public func integer(forKey key: UserDefaultsKey<Int>) -> Int {
                    integerCallCount += 1
                    integerCallArgs.append(key)
                    guard let _handler = integerHandler else {
                        fatalError("\\(Self.self).integerHandler is not set")
                    }
                    return _handler(key)
                }
                public var setIntegerCallCount: Int = 0
                public var setIntegerCallArgs: [(value: Int, key: UserDefaultsKey<Int>)] = []
                public var setIntegerHandler: (@Sendable ((value: Int, key: UserDefaultsKey<Int>)) -> Void)?
                public func setInteger(_ value: Int, forKey key: UserDefaultsKey<Int>) {
                    setIntegerCallCount += 1
                    setIntegerCallArgs.append((value: value, key: key))
                    if let _handler = setIntegerHandler {
                        _handler((value: value, key: key))
                    }
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Sendable protocol generates thread-safe mock with Mutex")
    func sendableProtocol() {
        assertMacroExpansion(
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
                        _storage.withLock { $0.saveCallCount }
                    }
                    set {
                        _storage.withLock { $0.saveCallCount = newValue }
                    }
                }
                public var saveCallArgs: [(data: Data, key: String)] {
                    get {
                        _storage.withLock { $0.saveCallArgs }
                    }
                    set {
                        _storage.withLock { $0.saveCallArgs = newValue }
                    }
                }
                public var saveHandler: (@Sendable ((data: Data, key: String)) throws -> Void)? {
                    get {
                        _storage.withLock { $0.saveHandler }
                    }
                    set {
                        _storage.withLock { $0.saveHandler = newValue }
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
                        _storage.withLock { $0.loadCallCount }
                    }
                    set {
                        _storage.withLock { $0.loadCallCount = newValue }
                    }
                }
                public var loadCallArgs: [String] {
                    get {
                        _storage.withLock { $0.loadCallArgs }
                    }
                    set {
                        _storage.withLock { $0.loadCallArgs = newValue }
                    }
                }
                public var loadHandler: (@Sendable (String) throws -> Data?)? {
                    get {
                        _storage.withLock { $0.loadHandler }
                    }
                    set {
                        _storage.withLock { $0.loadHandler = newValue }
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
                        _storage.withLock { $0.deleteCallCount }
                    }
                    set {
                        _storage.withLock { $0.deleteCallCount = newValue }
                    }
                }
                public var deleteCallArgs: [String] {
                    get {
                        _storage.withLock { $0.deleteCallArgs }
                    }
                    set {
                        _storage.withLock { $0.deleteCallArgs = newValue }
                    }
                }
                public var deleteHandler: (@Sendable (String) throws -> Void)? {
                    get {
                        _storage.withLock { $0.deleteHandler }
                    }
                    set {
                        _storage.withLock { $0.deleteHandler = newValue }
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
                        _storage.withLock { $0.existsCallCount }
                    }
                    set {
                        _storage.withLock { $0.existsCallCount = newValue }
                    }
                }
                public var existsCallArgs: [String] {
                    get {
                        _storage.withLock { $0.existsCallArgs }
                    }
                    set {
                        _storage.withLock { $0.existsCallArgs = newValue }
                    }
                }
                public var existsHandler: (@Sendable (String) -> Bool)? {
                    get {
                        _storage.withLock { $0.existsHandler }
                    }
                    set {
                        _storage.withLock { $0.existsHandler = newValue }
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
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Sendable protocol with @Sendable attribute")
    func sendableProtocolWithAttribute() {
        assertMacroExpansion(
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

            @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
            public final class LoggerMock: Logger, Sendable {
                private struct Storage {
                    var logCallCount: Int = 0
                    var logCallArgs: [String] = []
                    var logHandler: (@Sendable (String) -> Void)? = nil
                }
                private let _storage = Mutex<Storage>(Storage())
                public var logCallCount: Int {
                    get {
                        _storage.withLock { $0.logCallCount }
                    }
                    set {
                        _storage.withLock { $0.logCallCount = newValue }
                    }
                }
                public var logCallArgs: [String] {
                    get {
                        _storage.withLock { $0.logCallArgs }
                    }
                    set {
                        _storage.withLock { $0.logCallArgs = newValue }
                    }
                }
                public var logHandler: (@Sendable (String) -> Void)? {
                    get {
                        _storage.withLock { $0.logHandler }
                    }
                    set {
                        _storage.withLock { $0.logHandler = newValue }
                    }
                }
                public func log(message: String) {
                    let _handler = _storage.withLock { storage -> (@Sendable (String) -> Void)? in
                        storage.logCallCount += 1
                        storage.logCallArgs.append(message)
                        return storage.logHandler
                    }
                    if let _handler {
                        _handler(message)
                    }
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with @escaping closure parameter")
    func escapingClosureParameter() {
        assertMacroExpansion(
            """
            @Mockable
            protocol EventHandler {
                func subscribe(handler: @escaping (String) -> Void)
            }
            """,
            expandedSource: """
            protocol EventHandler {
                func subscribe(handler: @escaping (String) -> Void)
            }
            #if DEBUG

            public class EventHandlerMock: EventHandler {
                public var subscribeCallCount: Int = 0
                public var subscribeCallArgs: [(String) -> Void] = []
                public var subscribeHandler: (@Sendable ((String) -> Void) -> Void)?
                public func subscribe(handler: @escaping (String) -> Void) {
                    subscribeCallCount += 1
                    subscribeCallArgs.append(handler)
                    if let _handler = subscribeHandler {
                        _handler(handler)
                    }
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with @escaping @Sendable closure parameter")
    func escapingSendableClosureParameter() {
        assertMacroExpansion(
            """
            @Mockable
            protocol EventHandler {
                func onEvent(callback: @escaping @Sendable (Int) -> Void)
            }
            """,
            expandedSource: """
            protocol EventHandler {
                func onEvent(callback: @escaping @Sendable (Int) -> Void)
            }
            #if DEBUG

            public class EventHandlerMock: EventHandler {
                public var onEventCallCount: Int = 0
                public var onEventCallArgs: [@Sendable (Int) -> Void] = []
                public var onEventHandler: (@Sendable (@Sendable (Int) -> Void) -> Void)?
                public func onEvent(callback: @escaping @Sendable (Int) -> Void) {
                    onEventCallCount += 1
                    onEventCallArgs.append(callback)
                    if let _handler = onEventHandler {
                        _handler(callback)
                    }
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Sendable protocol with @escaping @Sendable closure parameter")
    func sendableProtocolWithEscapingClosure() {
        assertMacroExpansion(
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

            @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
            public final class EventServiceMock: EventService, Sendable {
                private struct Storage {
                    var registerCallCount: Int = 0
                    var registerCallArgs: [@Sendable (String) -> Void] = []
                    var registerHandler: (@Sendable (@Sendable (String) -> Void) async -> Void)? = nil
                }
                private let _storage = Mutex<Storage>(Storage())
                public var registerCallCount: Int {
                    get {
                        _storage.withLock { $0.registerCallCount }
                    }
                    set {
                        _storage.withLock { $0.registerCallCount = newValue }
                    }
                }
                public var registerCallArgs: [@Sendable (String) -> Void] {
                    get {
                        _storage.withLock { $0.registerCallArgs }
                    }
                    set {
                        _storage.withLock { $0.registerCallArgs = newValue }
                    }
                }
                public var registerHandler: (@Sendable (@Sendable (String) -> Void) async -> Void)? {
                    get {
                        _storage.withLock { $0.registerHandler }
                    }
                    set {
                        _storage.withLock { $0.registerHandler = newValue }
                    }
                }
                public func register(handler: @escaping @Sendable (String) -> Void) async {
                    let _handler = _storage.withLock { storage -> (@Sendable (@Sendable (String) -> Void) async -> Void)? in
                        storage.registerCallCount += 1
                        storage.registerCallArgs.append(handler)
                        return storage.registerHandler
                    }
                    if let _handler {
                        await _handler(handler)
                    }
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Sendable protocol with property")
    func sendableProtocolWithProperty() {
        assertMacroExpansion(
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

            @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
            public final class ConfigProviderMock: ConfigProvider, Sendable {
                private struct Storage {
                    var _apiKey: String? = nil
                    var _timeout: Int? = nil
                }
                private let _storage = Mutex<Storage>(Storage())
                public var _apiKey: String? {
                    get {
                        _storage.withLock { $0._apiKey }
                    }
                    set {
                        _storage.withLock { $0._apiKey = newValue }
                    }
                }
                public var apiKey: String {
                    _storage.withLock { $0._apiKey! }
                }
                public var timeout: Int {
                    get {
                        _storage.withLock { $0._timeout! }
                    }
                    set {
                        _storage.withLock { $0._timeout = newValue }
                    }
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Actor protocol generates actor mock")
    func actorProtocol() {
        assertMacroExpansion(
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

            @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
            public actor UserProfileStoreMock: UserProfileStore {
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
                public nonisolated var _profiles: [String: String]? {
                    get {
                        _storage.withLock { $0._profiles }
                    }
                    set {
                        _storage.withLock { $0._profiles = newValue }
                    }
                }
                public var profiles: [String: String] {
                    _storage.withLock { $0._profiles! }
                }
                public nonisolated var updateProfileCallCount: Int {
                    get {
                        _storage.withLock { $0.updateProfileCallCount }
                    }
                    set {
                        _storage.withLock { $0.updateProfileCallCount = newValue }
                    }
                }
                public nonisolated var updateProfileCallArgs: [(profile: String, key: String)] {
                    get {
                        _storage.withLock { $0.updateProfileCallArgs }
                    }
                    set {
                        _storage.withLock { $0.updateProfileCallArgs = newValue }
                    }
                }
                public nonisolated var updateProfileHandler: (@Sendable ((profile: String, key: String)) -> Void)? {
                    get {
                        _storage.withLock { $0.updateProfileHandler }
                    }
                    set {
                        _storage.withLock { $0.updateProfileHandler = newValue }
                    }
                }
                public func updateProfile(_ profile: String, for key: String) {
                    let _handler = _storage.withLock { storage -> (@Sendable ((profile: String, key: String)) -> Void)? in
                        storage.updateProfileCallCount += 1
                        storage.updateProfileCallArgs.append((profile: profile, key: key))
                        return storage.updateProfileHandler
                    }
                    if let _handler {
                        _handler((profile: profile, key: key))
                    }
                }
                public nonisolated var profileCallCount: Int {
                    get {
                        _storage.withLock { $0.profileCallCount }
                    }
                    set {
                        _storage.withLock { $0.profileCallCount = newValue }
                    }
                }
                public nonisolated var profileCallArgs: [String] {
                    get {
                        _storage.withLock { $0.profileCallArgs }
                    }
                    set {
                        _storage.withLock { $0.profileCallArgs = newValue }
                    }
                }
                public nonisolated var profileHandler: (@Sendable (String) -> String?)? {
                    get {
                        _storage.withLock { $0.profileHandler }
                    }
                    set {
                        _storage.withLock { $0.profileHandler = newValue }
                    }
                }
                public func profile(for key: String) -> String? {
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
                public nonisolated var resetCallCount: Int {
                    get {
                        _storage.withLock { $0.resetCallCount }
                    }
                    set {
                        _storage.withLock { $0.resetCallCount = newValue }
                    }
                }
                public nonisolated var resetCallArgs: [()] {
                    get {
                        _storage.withLock { $0.resetCallArgs }
                    }
                    set {
                        _storage.withLock { $0.resetCallArgs = newValue }
                    }
                }
                public nonisolated var resetHandler: (@Sendable () -> Void)? {
                    get {
                        _storage.withLock { $0.resetHandler }
                    }
                    set {
                        _storage.withLock { $0.resetHandler = newValue }
                    }
                }
                public func reset() {
                    let _handler = _storage.withLock { storage -> (@Sendable () -> Void)? in
                        storage.resetCallCount += 1
                        storage.resetCallArgs.append(())
                        return storage.resetHandler
                    }
                    if let _handler {
                        _handler()
                    }
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Actor protocol with async throws method")
    func actorProtocolWithAsyncThrows() {
        assertMacroExpansion(
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

            @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
            public actor DataStoreMock: DataStore {
                private struct Storage {
                    var saveCallCount: Int = 0
                    var saveCallArgs: [String] = []
                    var saveHandler: (@Sendable (String) async throws -> Void)? = nil
                    var loadCallCount: Int = 0
                    var loadCallArgs: [()] = []
                    var loadHandler: (@Sendable () async throws -> String)? = nil
                }
                private let _storage = Mutex<Storage>(Storage())
                public nonisolated var saveCallCount: Int {
                    get {
                        _storage.withLock { $0.saveCallCount }
                    }
                    set {
                        _storage.withLock { $0.saveCallCount = newValue }
                    }
                }
                public nonisolated var saveCallArgs: [String] {
                    get {
                        _storage.withLock { $0.saveCallArgs }
                    }
                    set {
                        _storage.withLock { $0.saveCallArgs = newValue }
                    }
                }
                public nonisolated var saveHandler: (@Sendable (String) async throws -> Void)? {
                    get {
                        _storage.withLock { $0.saveHandler }
                    }
                    set {
                        _storage.withLock { $0.saveHandler = newValue }
                    }
                }
                public func save(_ data: String) async throws {
                    let _handler = _storage.withLock { storage -> (@Sendable (String) async throws -> Void)? in
                        storage.saveCallCount += 1
                        storage.saveCallArgs.append(data)
                        return storage.saveHandler
                    }
                    if let _handler {
                        try await _handler(data)
                    }
                }
                public nonisolated var loadCallCount: Int {
                    get {
                        _storage.withLock { $0.loadCallCount }
                    }
                    set {
                        _storage.withLock { $0.loadCallCount = newValue }
                    }
                }
                public nonisolated var loadCallArgs: [()] {
                    get {
                        _storage.withLock { $0.loadCallArgs }
                    }
                    set {
                        _storage.withLock { $0.loadCallArgs = newValue }
                    }
                }
                public nonisolated var loadHandler: (@Sendable () async throws -> String)? {
                    get {
                        _storage.withLock { $0.loadHandler }
                    }
                    set {
                        _storage.withLock { $0.loadHandler = newValue }
                    }
                }
                public func load() async throws -> String {
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
            }
            #endif
            """,
            macros: testMacros
        )
    }
}
