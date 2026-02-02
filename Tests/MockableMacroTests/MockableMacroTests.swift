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
        assertMacroExpansionForTesting(
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
                public var fetchUserHandler: (@Sendable (Int) -> String)? = nil
                public func fetchUser(id: Int) -> String {
                    fetchUserCallCount += 1
                    fetchUserCallArgs.append(id)
                    guard let _handler = fetchUserHandler else {
                        fatalError("\\(Self.self).fetchUserHandler is not set")
                    }
                    return _handler(id)
                }
                public func resetMock() {
                    fetchUserCallCount = 0
                    fetchUserCallArgs = []
                    fetchUserHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with async throws method")
    func asyncThrowsMethod() {
        assertMacroExpansionForTesting(
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
                public var loadDataHandler: (@Sendable (String) async throws -> Data)? = nil
                public func loadData(from url: String) async throws -> Data {
                    loadDataCallCount += 1
                    loadDataCallArgs.append(url)
                    guard let _handler = loadDataHandler else {
                        fatalError("\\(Self.self).loadDataHandler is not set")
                    }
                    return try await _handler(url)
                }
                public func resetMock() {
                    loadDataCallCount = 0
                    loadDataCallArgs = []
                    loadDataHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with multiple parameters")
    func multipleParameters() {
        assertMacroExpansionForTesting(
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
                public var addHandler: (@Sendable ((a: Int, b: Int)) -> Int)? = nil
                public func add(a: Int, b: Int) -> Int {
                    addCallCount += 1
                    addCallArgs.append((a: a, b: b))
                    guard let _handler = addHandler else {
                        fatalError("\\(Self.self).addHandler is not set")
                    }
                    return _handler((a: a, b: b))
                }
                public func resetMock() {
                    addCallCount = 0
                    addCallArgs = []
                    addHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with void method")
    func voidMethod() {
        assertMacroExpansionForTesting(
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
                public var logHandler: (@Sendable (String) -> Void)? = nil
                public func log(message: String) {
                    logCallCount += 1
                    logCallArgs.append(message)
                    if let _handler = logHandler {
                        _handler(message)
                    }
                }
                public func resetMock() {
                    logCallCount = 0
                    logCallArgs = []
                    logHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with get-only property")
    func getOnlyProperty() {
        assertMacroExpansionForTesting(
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
                public var _currentUser: String? = nil
                public var currentUser: String {
                    _currentUser!
                }
                public func resetMock() {
                    _currentUser = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with get-set property")
    func getSetProperty() {
        assertMacroExpansionForTesting(
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
                public func resetMock() {
                    _theme = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with optional property")
    func optionalProperty() {
        assertMacroExpansionForTesting(
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
                public func resetMock() {
                    lastValue = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Non-protocol declaration should fail")
    func nonProtocolFails() {
        assertMacroExpansionForTesting(
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
        assertMacroExpansionForTesting(
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
                public var getHandler: (@Sendable (String) -> Any)? = nil
                public func get<T>(_ key: String) -> T {
                    getCallCount += 1
                    getCallArgs.append(key)
                    guard let _handler = getHandler else {
                        fatalError("\\(Self.self).getHandler is not set")
                    }
                    return _handler(key) as! T
                }
                public func resetMock() {
                    getCallCount = 0
                    getCallArgs = []
                    getHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with generic method with generic parameter type")
    func genericMethodWithGenericParameter() {
        assertMacroExpansionForTesting(
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
                public var saveHandler: (@Sendable ((value: Any, key: String)) -> Void)? = nil
                public func save<T>(_ value: T, forKey key: String) {
                    saveCallCount += 1
                    saveCallArgs.append((value: value, key: key))
                    if let _handler = saveHandler {
                        _handler((value: value, key: key))
                    }
                }
                public func resetMock() {
                    saveCallCount = 0
                    saveCallArgs = []
                    saveHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with generic method using wrapper type like UserDefaultsKey<T>")
    func genericMethodWithWrapperType() {
        assertMacroExpansionForTesting(
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
                public var getHandler: (@Sendable (Any) -> Any)? = nil
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
                public var setHandler: (@Sendable ((value: Any, key: Any)) -> Void)? = nil
                public func set<T>(_ value: T, forKey key: UserDefaultsKey<T>) {
                    setCallCount += 1
                    setCallArgs.append((value: value, key: key))
                    if let _handler = setHandler {
                        _handler((value: value, key: key))
                    }
                }
                public func resetMock() {
                    getCallCount = 0
                    getCallArgs = []
                    getHandler = nil
                    setCallCount = 0
                    setCallArgs = []
                    setHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with concrete generic type parameters (non-generic method)")
    func concreteGenericTypeParameters() {
        assertMacroExpansionForTesting(
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
                public var integerHandler: (@Sendable (UserDefaultsKey<Int>) -> Int)? = nil
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
                public var setIntegerHandler: (@Sendable ((value: Int, key: UserDefaultsKey<Int>)) -> Void)? = nil
                public func setInteger(_ value: Int, forKey key: UserDefaultsKey<Int>) {
                    setIntegerCallCount += 1
                    setIntegerCallArgs.append((value: value, key: key))
                    if let _handler = setIntegerHandler {
                        _handler((value: value, key: key))
                    }
                }
                public func resetMock() {
                    integerCallCount = 0
                    integerCallArgs = []
                    integerHandler = nil
                    setIntegerCallCount = 0
                    setIntegerCallArgs = []
                    setIntegerHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

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
            public final class LoggerMock: Logger, Sendable {
                private struct Storage {
                    var logCallCount: Int = 0
                    var logCallArgs: [String] = []
                    var logHandler: (@Sendable (String) -> Void)? = nil
                }
                private let _storage = Mutex<Storage>(Storage())
                public var logCallCount: Int {
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
                public var logCallArgs: [String] {
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
                public var logHandler: (@Sendable (String) -> Void)? {
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
                public func resetMock() {
                    _storage.withLock { storage in
                        storage.logCallCount = 0
                        storage.logCallArgs = []
                        storage.logHandler = nil
                    }
                }
            }
            #else
            public final class LoggerMock: Logger, Sendable {
                private struct Storage {
                    var logCallCount: Int = 0
                    var logCallArgs: [String] = []
                    var logHandler: (@Sendable (String) -> Void)? = nil
                }
                private let _storage = LegacyLock<Storage>(Storage())
                public var logCallCount: Int {
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
                public var logCallArgs: [String] {
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
                public var logHandler: (@Sendable (String) -> Void)? {
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
                public func resetMock() {
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

    @Test("Protocol with @escaping closure parameter")
    func escapingClosureParameter() {
        assertMacroExpansionForTesting(
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
                public var subscribeHandler: (@Sendable ((String) -> Void) -> Void)? = nil
                public func subscribe(handler: @escaping (String) -> Void) {
                    subscribeCallCount += 1
                    subscribeCallArgs.append(handler)
                    if let _handler = subscribeHandler {
                        _handler(handler)
                    }
                }
                public func resetMock() {
                    subscribeCallCount = 0
                    subscribeCallArgs = []
                    subscribeHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with @escaping @Sendable closure parameter")
    func escapingSendableClosureParameter() {
        assertMacroExpansionForTesting(
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
                public var onEventHandler: (@Sendable (@Sendable (Int) -> Void) -> Void)? = nil
                public func onEvent(callback: @escaping @Sendable (Int) -> Void) {
                    onEventCallCount += 1
                    onEventCallArgs.append(callback)
                    if let _handler = onEventHandler {
                        _handler(callback)
                    }
                }
                public func resetMock() {
                    onEventCallCount = 0
                    onEventCallArgs = []
                    onEventHandler = nil
                }
            }
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
            public final class EventServiceMock: EventService, Sendable {
                private struct Storage {
                    var registerCallCount: Int = 0
                    var registerCallArgs: [@Sendable (String) -> Void] = []
                    var registerHandler: (@Sendable (@Sendable (String) -> Void) async -> Void)? = nil
                }
                private let _storage = Mutex<Storage>(Storage())
                public var registerCallCount: Int {
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
                public var registerCallArgs: [@Sendable (String) -> Void] {
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
                public var registerHandler: (@Sendable (@Sendable (String) -> Void) async -> Void)? {
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
                public func resetMock() {
                    _storage.withLock { storage in
                        storage.registerCallCount = 0
                        storage.registerCallArgs = []
                        storage.registerHandler = nil
                    }
                }
            }
            #else
            public final class EventServiceMock: EventService, Sendable {
                private struct Storage {
                    var registerCallCount: Int = 0
                    var registerCallArgs: [@Sendable (String) -> Void] = []
                    var registerHandler: (@Sendable (@Sendable (String) -> Void) async -> Void)? = nil
                }
                private let _storage = LegacyLock<Storage>(Storage())
                public var registerCallCount: Int {
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
                public var registerCallArgs: [@Sendable (String) -> Void] {
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
                public var registerHandler: (@Sendable (@Sendable (String) -> Void) async -> Void)? {
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
                public func resetMock() {
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
            public final class ConfigProviderMock: ConfigProvider, Sendable {
                private struct Storage {
                    var _apiKey: String? = nil
                    var _timeout: Int? = nil
                }
                private let _storage = Mutex<Storage>(Storage())
                public var _apiKey: String? {
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
                public var apiKey: String {
                    _storage.withLock {
                        $0._apiKey!
                    }
                }
                public var timeout: Int {
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
                public func resetMock() {
                    _storage.withLock { storage in
                        storage._apiKey = nil
                        storage._timeout = nil
                    }
                }
            }
            #else
            public final class ConfigProviderMock: ConfigProvider, Sendable {
                private struct Storage {
                    var _apiKey: String? = nil
                    var _timeout: Int? = nil
                }
                private let _storage = LegacyLock<Storage>(Storage())
                public var _apiKey: String? {
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
                public var apiKey: String {
                    _storage.withLock {
                        $0._apiKey!
                    }
                }
                public var timeout: Int {
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
                public func resetMock() {
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
                public var profiles: [String: String] {
                    _storage.withLock {
                        $0._profiles!
                    }
                }
                public nonisolated var updateProfileCallCount: Int {
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
                public nonisolated var updateProfileCallArgs: [(profile: String, key: String)] {
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
                public nonisolated var updateProfileHandler: (@Sendable ((profile: String, key: String)) -> Void)? {
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
                public nonisolated var profileCallArgs: [String] {
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
                public nonisolated var profileHandler: (@Sendable (String) -> String?)? {
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
                public nonisolated var resetCallArgs: [()] {
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
                public nonisolated var resetHandler: (@Sendable () -> Void)? {
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
                public nonisolated func resetMock() {
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
                private let _storage = LegacyLock<Storage>(Storage())
                public nonisolated var _profiles: [String: String]? {
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
                public var profiles: [String: String] {
                    _storage.withLock {
                        $0._profiles!
                    }
                }
                public nonisolated var updateProfileCallCount: Int {
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
                public nonisolated var updateProfileCallArgs: [(profile: String, key: String)] {
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
                public nonisolated var updateProfileHandler: (@Sendable ((profile: String, key: String)) -> Void)? {
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
                public nonisolated var profileCallArgs: [String] {
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
                public nonisolated var profileHandler: (@Sendable (String) -> String?)? {
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
                public nonisolated var resetCallArgs: [()] {
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
                public nonisolated var resetHandler: (@Sendable () -> Void)? {
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
                public nonisolated func resetMock() {
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
            public actor ConfigProviderMock: ConfigProvider {
                private struct Storage {
                    var _apiKey: String? = nil
                    var _timeout: Int? = nil
                }
                private let _storage = Mutex<Storage>(Storage())
                public nonisolated var _apiKey: String? {
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
                public var apiKey: String {
                    _storage.withLock {
                        $0._apiKey!
                    }
                }
                public nonisolated var _timeout: Int? {
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
                public var timeout: Int {
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
                public nonisolated func resetMock() {
                    _storage.withLock { storage in
                        storage._apiKey = nil
                        storage._timeout = nil
                    }
                }
            }
            #else
            public actor ConfigProviderMock: ConfigProvider {
                private struct Storage {
                    var _apiKey: String? = nil
                    var _timeout: Int? = nil
                }
                private let _storage = LegacyLock<Storage>(Storage())
                public nonisolated var _apiKey: String? {
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
                public var apiKey: String {
                    _storage.withLock {
                        $0._apiKey!
                    }
                }
                public nonisolated var _timeout: Int? {
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
                public var timeout: Int {
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
                public nonisolated func resetMock() {
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
                public nonisolated var saveCallArgs: [String] {
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
                public nonisolated var saveHandler: (@Sendable (String) async throws -> Void)? {
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
                public nonisolated var loadCallArgs: [()] {
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
                public nonisolated var loadHandler: (@Sendable () async throws -> String)? {
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
                public nonisolated func resetMock() {
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
            public actor DataStoreMock: DataStore {
                private struct Storage {
                    var saveCallCount: Int = 0
                    var saveCallArgs: [String] = []
                    var saveHandler: (@Sendable (String) async throws -> Void)? = nil
                    var loadCallCount: Int = 0
                    var loadCallArgs: [()] = []
                    var loadHandler: (@Sendable () async throws -> String)? = nil
                }
                private let _storage = LegacyLock<Storage>(Storage())
                public nonisolated var saveCallCount: Int {
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
                public nonisolated var saveCallArgs: [String] {
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
                public nonisolated var saveHandler: (@Sendable (String) async throws -> Void)? {
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
                public nonisolated var loadCallArgs: [()] {
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
                public nonisolated var loadHandler: (@Sendable () async throws -> String)? {
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
                public nonisolated func resetMock() {
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

    @Test("Protocol with associated type without default")
    func associatedTypeWithoutDefault() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol DataStore {
                associatedtype Model
                func fetch() -> Model
                func save(_ model: Model)
            }
            """,
            expandedSource: """
            protocol DataStore {
                associatedtype Model
                func fetch() -> Model
                func save(_ model: Model)
            }

            #if DEBUG
            public class DataStoreMock: DataStore {
                public typealias Model = Any
                public var fetchCallCount: Int = 0
                public var fetchCallArgs: [()] = []
                public var fetchHandler: (@Sendable () -> Model)? = nil
                public func fetch() -> Model {
                    fetchCallCount += 1
                    fetchCallArgs.append(())
                    guard let _handler = fetchHandler else {
                        fatalError("\\(Self.self).fetchHandler is not set")
                    }
                    return _handler()
                }
                public var saveCallCount: Int = 0
                public var saveCallArgs: [Model] = []
                public var saveHandler: (@Sendable (Model) -> Void)? = nil
                public func save(_ model: Model) {
                    saveCallCount += 1
                    saveCallArgs.append(model)
                    if let _handler = saveHandler {
                        _handler(model)
                    }
                }
                public func resetMock() {
                    fetchCallCount = 0
                    fetchCallArgs = []
                    fetchHandler = nil
                    saveCallCount = 0
                    saveCallArgs = []
                    saveHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with associated type with default type")
    func associatedTypeWithDefault() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol StringStore {
                associatedtype Element = String
                func get() -> Element
            }
            """,
            expandedSource: """
            protocol StringStore {
                associatedtype Element = String
                func get() -> Element
            }

            #if DEBUG
            public class StringStoreMock: StringStore {
                public typealias Element = String
                public var getCallCount: Int = 0
                public var getCallArgs: [()] = []
                public var getHandler: (@Sendable () -> Element)? = nil
                public func get() -> Element {
                    getCallCount += 1
                    getCallArgs.append(())
                    guard let _handler = getHandler else {
                        fatalError("\\(Self.self).getHandler is not set")
                    }
                    return _handler()
                }
                public func resetMock() {
                    getCallCount = 0
                    getCallArgs = []
                    getHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with multiple associated types")
    func multipleAssociatedTypes() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Repository {
                associatedtype Entity
                associatedtype ID = String
                func find(by id: ID) -> Entity?
                func save(_ entity: Entity) -> ID
            }
            """,
            expandedSource: """
            protocol Repository {
                associatedtype Entity
                associatedtype ID = String
                func find(by id: ID) -> Entity?
                func save(_ entity: Entity) -> ID
            }

            #if DEBUG
            public class RepositoryMock: Repository {
                public typealias Entity = Any
                public typealias ID = String
                public var findCallCount: Int = 0
                public var findCallArgs: [ID] = []
                public var findHandler: (@Sendable (ID) -> Entity?)? = nil
                public func find(by id: ID) -> Entity? {
                    findCallCount += 1
                    findCallArgs.append(id)
                    guard let _handler = findHandler else {
                        fatalError("\\(Self.self).findHandler is not set")
                    }
                    return _handler(id)
                }
                public var saveCallCount: Int = 0
                public var saveCallArgs: [Entity] = []
                public var saveHandler: (@Sendable (Entity) -> ID)? = nil
                public func save(_ entity: Entity) -> ID {
                    saveCallCount += 1
                    saveCallArgs.append(entity)
                    guard let _handler = saveHandler else {
                        fatalError("\\(Self.self).saveHandler is not set")
                    }
                    return _handler(entity)
                }
                public func resetMock() {
                    findCallCount = 0
                    findCallArgs = []
                    findHandler = nil
                    saveCallCount = 0
                    saveCallArgs = []
                    saveHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Sendable protocol with associated type")
    func sendableProtocolWithAssociatedType() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol AsyncStore: Sendable {
                associatedtype Item = String
                func fetch() async -> Item
            }
            """,
            expandedSource: """
            protocol AsyncStore: Sendable {
                associatedtype Item = String
                func fetch() async -> Item
            }

            #if DEBUG
            #if canImport(Synchronization)
            @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
            public final class AsyncStoreMock: AsyncStore, Sendable {
                public typealias Item = String
                private struct Storage {
                    var fetchCallCount: Int = 0
                    var fetchCallArgs: [()] = []
                    var fetchHandler: (@Sendable () async -> Item)? = nil
                }
                private let _storage = Mutex<Storage>(Storage())
                public var fetchCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.fetchCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.fetchCallCount = newValue
                        }
                    }
                }
                public var fetchCallArgs: [()] {
                    get {
                        _storage.withLock {
                            $0.fetchCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.fetchCallArgs = newValue
                        }
                    }
                }
                public var fetchHandler: (@Sendable () async -> Item)? {
                    get {
                        _storage.withLock {
                            $0.fetchHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.fetchHandler = newValue
                        }
                    }
                }
                public func fetch() async -> Item {
                    let _handler = _storage.withLock { storage -> (@Sendable () async -> Item)? in
                        storage.fetchCallCount += 1
                        storage.fetchCallArgs.append(())
                        return storage.fetchHandler
                    }
                    guard let _handler else {
                        fatalError("\\(Self.self).fetchHandler is not set")
                    }
                    return await _handler()
                }
                public func resetMock() {
                    _storage.withLock { storage in
                        storage.fetchCallCount = 0
                        storage.fetchCallArgs = []
                        storage.fetchHandler = nil
                    }
                }
            }
            #else
            public final class AsyncStoreMock: AsyncStore, Sendable {
                public typealias Item = String
                private struct Storage {
                    var fetchCallCount: Int = 0
                    var fetchCallArgs: [()] = []
                    var fetchHandler: (@Sendable () async -> Item)? = nil
                }
                private let _storage = LegacyLock<Storage>(Storage())
                public var fetchCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.fetchCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.fetchCallCount = newValue
                        }
                    }
                }
                public var fetchCallArgs: [()] {
                    get {
                        _storage.withLock {
                            $0.fetchCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.fetchCallArgs = newValue
                        }
                    }
                }
                public var fetchHandler: (@Sendable () async -> Item)? {
                    get {
                        _storage.withLock {
                            $0.fetchHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.fetchHandler = newValue
                        }
                    }
                }
                public func fetch() async -> Item {
                    let _handler = _storage.withLock { storage -> (@Sendable () async -> Item)? in
                        storage.fetchCallCount += 1
                        storage.fetchCallArgs.append(())
                        return storage.fetchHandler
                    }
                    guard let _handler else {
                        fatalError("\\(Self.self).fetchHandler is not set")
                    }
                    return await _handler()
                }
                public func resetMock() {
                    _storage.withLock { storage in
                        storage.fetchCallCount = 0
                        storage.fetchCallArgs = []
                        storage.fetchHandler = nil
                    }
                }
            }
            #endif
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Actor protocol with associated type")
    func actorProtocolWithAssociatedType() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol CacheActor: Actor {
                associatedtype Value = Data
                func get(key: String) -> Value?
                func set(key: String, value: Value)
            }
            """,
            expandedSource: """
            protocol CacheActor: Actor {
                associatedtype Value = Data
                func get(key: String) -> Value?
                func set(key: String, value: Value)
            }

            #if DEBUG
            #if canImport(Synchronization)
            @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
            public actor CacheActorMock: CacheActor {
                public typealias Value = Data
                private struct Storage {
                    var getCallCount: Int = 0
                    var getCallArgs: [String] = []
                    var getHandler: (@Sendable (String) -> Value?)? = nil
                    var setCallCount: Int = 0
                    var setCallArgs: [(key: String, value: Value)] = []
                    var setHandler: (@Sendable ((key: String, value: Value)) -> Void)? = nil
                }
                private let _storage = Mutex<Storage>(Storage())
                public nonisolated var getCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.getCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.getCallCount = newValue
                        }
                    }
                }
                public nonisolated var getCallArgs: [String] {
                    get {
                        _storage.withLock {
                            $0.getCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.getCallArgs = newValue
                        }
                    }
                }
                public nonisolated var getHandler: (@Sendable (String) -> Value?)? {
                    get {
                        _storage.withLock {
                            $0.getHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.getHandler = newValue
                        }
                    }
                }
                public func get(key: String) -> Value? {
                    let _handler = _storage.withLock { storage -> (@Sendable (String) -> Value?)? in
                        storage.getCallCount += 1
                        storage.getCallArgs.append(key)
                        return storage.getHandler
                    }
                    guard let _handler else {
                        fatalError("\\(Self.self).getHandler is not set")
                    }
                    return _handler(key)
                }
                public nonisolated var setCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.setCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.setCallCount = newValue
                        }
                    }
                }
                public nonisolated var setCallArgs: [(key: String, value: Value)] {
                    get {
                        _storage.withLock {
                            $0.setCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.setCallArgs = newValue
                        }
                    }
                }
                public nonisolated var setHandler: (@Sendable ((key: String, value: Value)) -> Void)? {
                    get {
                        _storage.withLock {
                            $0.setHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.setHandler = newValue
                        }
                    }
                }
                public func set(key: String, value: Value) {
                    let _handler = _storage.withLock { storage -> (@Sendable ((key: String, value: Value)) -> Void)? in
                        storage.setCallCount += 1
                        storage.setCallArgs.append((key: key, value: value))
                        return storage.setHandler
                    }
                    if let _handler {
                        _handler((key: key, value: value))
                    }
                }
                public nonisolated func resetMock() {
                    _storage.withLock { storage in
                        storage.getCallCount = 0
                        storage.getCallArgs = []
                        storage.getHandler = nil
                        storage.setCallCount = 0
                        storage.setCallArgs = []
                        storage.setHandler = nil
                    }
                }
            }
            #else
            public actor CacheActorMock: CacheActor {
                public typealias Value = Data
                private struct Storage {
                    var getCallCount: Int = 0
                    var getCallArgs: [String] = []
                    var getHandler: (@Sendable (String) -> Value?)? = nil
                    var setCallCount: Int = 0
                    var setCallArgs: [(key: String, value: Value)] = []
                    var setHandler: (@Sendable ((key: String, value: Value)) -> Void)? = nil
                }
                private let _storage = LegacyLock<Storage>(Storage())
                public nonisolated var getCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.getCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.getCallCount = newValue
                        }
                    }
                }
                public nonisolated var getCallArgs: [String] {
                    get {
                        _storage.withLock {
                            $0.getCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.getCallArgs = newValue
                        }
                    }
                }
                public nonisolated var getHandler: (@Sendable (String) -> Value?)? {
                    get {
                        _storage.withLock {
                            $0.getHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.getHandler = newValue
                        }
                    }
                }
                public func get(key: String) -> Value? {
                    let _handler = _storage.withLock { storage -> (@Sendable (String) -> Value?)? in
                        storage.getCallCount += 1
                        storage.getCallArgs.append(key)
                        return storage.getHandler
                    }
                    guard let _handler else {
                        fatalError("\\(Self.self).getHandler is not set")
                    }
                    return _handler(key)
                }
                public nonisolated var setCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.setCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.setCallCount = newValue
                        }
                    }
                }
                public nonisolated var setCallArgs: [(key: String, value: Value)] {
                    get {
                        _storage.withLock {
                            $0.setCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.setCallArgs = newValue
                        }
                    }
                }
                public nonisolated var setHandler: (@Sendable ((key: String, value: Value)) -> Void)? {
                    get {
                        _storage.withLock {
                            $0.setHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.setHandler = newValue
                        }
                    }
                }
                public func set(key: String, value: Value) {
                    let _handler = _storage.withLock { storage -> (@Sendable ((key: String, value: Value)) -> Void)? in
                        storage.setCallCount += 1
                        storage.setCallArgs.append((key: key, value: value))
                        return storage.setHandler
                    }
                    if let _handler {
                        _handler((key: key, value: value))
                    }
                }
                public nonisolated func resetMock() {
                    _storage.withLock { storage in
                        storage.getCallCount = 0
                        storage.getCallArgs = []
                        storage.getHandler = nil
                        storage.setCallCount = 0
                        storage.setCallArgs = []
                        storage.setHandler = nil
                    }
                }
            }
            #endif
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with associated type with type constraint")
    func associatedTypeWithConstraint() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol DecodableStore {
                associatedtype Item: Decodable
                func decode(from data: Data) -> Item
            }
            """,
            expandedSource: """
            protocol DecodableStore {
                associatedtype Item: Decodable
                func decode(from data: Data) -> Item
            }

            #if DEBUG
            public class DecodableStoreMock: DecodableStore {
                public typealias Item = Any
                public var decodeCallCount: Int = 0
                public var decodeCallArgs: [Data] = []
                public var decodeHandler: (@Sendable (Data) -> Item)? = nil
                public func decode(from data: Data) -> Item {
                    decodeCallCount += 1
                    decodeCallArgs.append(data)
                    guard let _handler = decodeHandler else {
                        fatalError("\\(Self.self).decodeHandler is not set")
                    }
                    return _handler(data)
                }
                public func resetMock() {
                    decodeCallCount = 0
                    decodeCallArgs = []
                    decodeHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with associated type used in property")
    func associatedTypeInProperty() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol StateHolder {
                associatedtype State = String
                var currentState: State { get }
                var previousState: State? { get set }
            }
            """,
            expandedSource: """
            protocol StateHolder {
                associatedtype State = String
                var currentState: State { get }
                var previousState: State? { get set }
            }

            #if DEBUG
            public class StateHolderMock: StateHolder {
                public typealias State = String
                public var _currentState: State? = nil
                public var currentState: State {
                    _currentState!
                }
                public var previousState: State? = nil
                public func resetMock() {
                    _currentState = nil
                    previousState = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with associated type with complex default type")
    func associatedTypeWithComplexDefault() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol ArrayStore {
                associatedtype Element = [String: Int]
                func getAll() -> Element
            }
            """,
            expandedSource: """
            protocol ArrayStore {
                associatedtype Element = [String: Int]
                func getAll() -> Element
            }

            #if DEBUG
            public class ArrayStoreMock: ArrayStore {
                public typealias Element = [String: Int]
                public var getAllCallCount: Int = 0
                public var getAllCallArgs: [()] = []
                public var getAllHandler: (@Sendable () -> Element)? = nil
                public func getAll() -> Element {
                    getAllCallCount += 1
                    getAllCallArgs.append(())
                    guard let _handler = getAllHandler else {
                        fatalError("\\(Self.self).getAllHandler is not set")
                    }
                    return _handler()
                }
                public func resetMock() {
                    getAllCallCount = 0
                    getAllCallArgs = []
                    getAllHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with associated type in optional return type")
    func associatedTypeInOptionalReturn() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol OptionalFetcher {
                associatedtype Result
                func fetch(id: String) -> Result?
            }
            """,
            expandedSource: """
            protocol OptionalFetcher {
                associatedtype Result
                func fetch(id: String) -> Result?
            }

            #if DEBUG
            public class OptionalFetcherMock: OptionalFetcher {
                public typealias Result = Any
                public var fetchCallCount: Int = 0
                public var fetchCallArgs: [String] = []
                public var fetchHandler: (@Sendable (String) -> Result?)? = nil
                public func fetch(id: String) -> Result? {
                    fetchCallCount += 1
                    fetchCallArgs.append(id)
                    guard let _handler = fetchHandler else {
                        fatalError("\\(Self.self).fetchHandler is not set")
                    }
                    return _handler(id)
                }
                public func resetMock() {
                    fetchCallCount = 0
                    fetchCallArgs = []
                    fetchHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with associated type in array parameter")
    func associatedTypeInArrayParameter() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol BatchProcessor {
                associatedtype Item = Int
                func process(items: [Item]) -> Int
            }
            """,
            expandedSource: """
            protocol BatchProcessor {
                associatedtype Item = Int
                func process(items: [Item]) -> Int
            }

            #if DEBUG
            public class BatchProcessorMock: BatchProcessor {
                public typealias Item = Int
                public var processCallCount: Int = 0
                public var processCallArgs: [[Item]] = []
                public var processHandler: (@Sendable ([Item]) -> Int)? = nil
                public func process(items: [Item]) -> Int {
                    processCallCount += 1
                    processCallArgs.append(items)
                    guard let _handler = processHandler else {
                        fatalError("\\(Self.self).processHandler is not set")
                    }
                    return _handler(items)
                }
                public func resetMock() {
                    processCallCount = 0
                    processCallArgs = []
                    processHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with associated type and async throws method")
    func associatedTypeWithAsyncThrows() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol AsyncRepository {
                associatedtype Entity
                func fetch(id: String) async throws -> Entity
                func save(_ entity: Entity) async throws
            }
            """,
            expandedSource: """
            protocol AsyncRepository {
                associatedtype Entity
                func fetch(id: String) async throws -> Entity
                func save(_ entity: Entity) async throws
            }

            #if DEBUG
            public class AsyncRepositoryMock: AsyncRepository {
                public typealias Entity = Any
                public var fetchCallCount: Int = 0
                public var fetchCallArgs: [String] = []
                public var fetchHandler: (@Sendable (String) async throws -> Entity)? = nil
                public func fetch(id: String) async throws -> Entity {
                    fetchCallCount += 1
                    fetchCallArgs.append(id)
                    guard let _handler = fetchHandler else {
                        fatalError("\\(Self.self).fetchHandler is not set")
                    }
                    return try await _handler(id)
                }
                public var saveCallCount: Int = 0
                public var saveCallArgs: [Entity] = []
                public var saveHandler: (@Sendable (Entity) async throws -> Void)? = nil
                public func save(_ entity: Entity) async throws {
                    saveCallCount += 1
                    saveCallArgs.append(entity)
                    if let _handler = saveHandler {
                        try await _handler(entity)
                    }
                }
                public func resetMock() {
                    fetchCallCount = 0
                    fetchCallArgs = []
                    fetchHandler = nil
                    saveCallCount = 0
                    saveCallArgs = []
                    saveHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Sendable protocol with associated type without default")
    func sendableProtocolWithAssociatedTypeNoDefault() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol ThreadSafeCache: Sendable {
                associatedtype Key
                associatedtype Value
                func get(key: Key) -> Value?
            }
            """,
            expandedSource: """
            protocol ThreadSafeCache: Sendable {
                associatedtype Key
                associatedtype Value
                func get(key: Key) -> Value?
            }

            #if DEBUG
            #if canImport(Synchronization)
            @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
            public final class ThreadSafeCacheMock: ThreadSafeCache, Sendable {
                public typealias Key = Any
                public typealias Value = Any
                private struct Storage {
                    var getCallCount: Int = 0
                    var getCallArgs: [Key] = []
                    var getHandler: (@Sendable (Key) -> Value?)? = nil
                }
                private let _storage = Mutex<Storage>(Storage())
                public var getCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.getCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.getCallCount = newValue
                        }
                    }
                }
                public var getCallArgs: [Key] {
                    get {
                        _storage.withLock {
                            $0.getCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.getCallArgs = newValue
                        }
                    }
                }
                public var getHandler: (@Sendable (Key) -> Value?)? {
                    get {
                        _storage.withLock {
                            $0.getHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.getHandler = newValue
                        }
                    }
                }
                public func get(key: Key) -> Value? {
                    let _handler = _storage.withLock { storage -> (@Sendable (Key) -> Value?)? in
                        storage.getCallCount += 1
                        storage.getCallArgs.append(key)
                        return storage.getHandler
                    }
                    guard let _handler else {
                        fatalError("\\(Self.self).getHandler is not set")
                    }
                    return _handler(key)
                }
                public func resetMock() {
                    _storage.withLock { storage in
                        storage.getCallCount = 0
                        storage.getCallArgs = []
                        storage.getHandler = nil
                    }
                }
            }
            #else
            public final class ThreadSafeCacheMock: ThreadSafeCache, Sendable {
                public typealias Key = Any
                public typealias Value = Any
                private struct Storage {
                    var getCallCount: Int = 0
                    var getCallArgs: [Key] = []
                    var getHandler: (@Sendable (Key) -> Value?)? = nil
                }
                private let _storage = LegacyLock<Storage>(Storage())
                public var getCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.getCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.getCallCount = newValue
                        }
                    }
                }
                public var getCallArgs: [Key] {
                    get {
                        _storage.withLock {
                            $0.getCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.getCallArgs = newValue
                        }
                    }
                }
                public var getHandler: (@Sendable (Key) -> Value?)? {
                    get {
                        _storage.withLock {
                            $0.getHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.getHandler = newValue
                        }
                    }
                }
                public func get(key: Key) -> Value? {
                    let _handler = _storage.withLock { storage -> (@Sendable (Key) -> Value?)? in
                        storage.getCallCount += 1
                        storage.getCallArgs.append(key)
                        return storage.getHandler
                    }
                    guard let _handler else {
                        fatalError("\\(Self.self).getHandler is not set")
                    }
                    return _handler(key)
                }
                public func resetMock() {
                    _storage.withLock { storage in
                        storage.getCallCount = 0
                        storage.getCallArgs = []
                        storage.getHandler = nil
                    }
                }
            }
            #endif
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with associated type and closure parameter")
    func associatedTypeWithClosure() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol EventEmitter {
                associatedtype Event = String
                func subscribe(handler: @escaping (Event) -> Void)
            }
            """,
            expandedSource: """
            protocol EventEmitter {
                associatedtype Event = String
                func subscribe(handler: @escaping (Event) -> Void)
            }

            #if DEBUG
            public class EventEmitterMock: EventEmitter {
                public typealias Event = String
                public var subscribeCallCount: Int = 0
                public var subscribeCallArgs: [(Event) -> Void] = []
                public var subscribeHandler: (@Sendable ((Event) -> Void) -> Void)? = nil
                public func subscribe(handler: @escaping (Event) -> Void) {
                    subscribeCallCount += 1
                    subscribeCallArgs.append(handler)
                    if let _handler = subscribeHandler {
                        _handler(handler)
                    }
                }
                public func resetMock() {
                    subscribeCallCount = 0
                    subscribeCallArgs = []
                    subscribeHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    // MARK: - Subscript Tests

    @Test("Protocol with get-only subscript")
    func getOnlySubscript() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Cache {
                subscript(key: String) -> Int { get }
            }
            """,
            expandedSource: """
            protocol Cache {
                subscript(key: String) -> Int { get }
            }

            #if DEBUG
            public class CacheMock: Cache {
                public var subscriptStringCallCount: Int = 0
                public var subscriptStringCallArgs: [String] = []
                public var subscriptStringHandler: (@Sendable (String) -> Int )? = nil
                public subscript(key: String) -> Int {
                    subscriptStringCallCount += 1
                    subscriptStringCallArgs.append(key)
                    guard let _handler = subscriptStringHandler else {
                        fatalError("\\(Self.self).subscriptStringHandler is not set")
                    }
                    return _handler(key)
                }
                public func resetMock() {
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

    @Test("Protocol with get-set subscript")
    func getSetSubscript() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Storage {
                subscript(index: Int) -> String { get set }
            }
            """,
            expandedSource: """
            protocol Storage {
                subscript(index: Int) -> String { get set }
            }

            #if DEBUG
            public class StorageMock: Storage {
                public var subscriptIntCallCount: Int = 0
                public var subscriptIntCallArgs: [Int] = []
                public var subscriptIntHandler: (@Sendable (Int) -> String )? = nil
                public var subscriptIntSetHandler: (@Sendable (Int, String ) -> Void)? = nil
                public subscript(index: Int) -> String {
                    get {
                        subscriptIntCallCount += 1
                        subscriptIntCallArgs.append(index)
                        guard let _handler = subscriptIntHandler else {
                            fatalError("\\(Self.self).subscriptIntHandler is not set")
                        }
                        return _handler(index)
                    }
                    set {
                        if let _handler = subscriptIntSetHandler {
                            _handler(index, newValue)
                        }
                    }
                }
                public func resetMock() {
                    subscriptIntCallCount = 0
                    subscriptIntCallArgs = []
                    subscriptIntHandler = nil
                    subscriptIntSetHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with multi-parameter subscript")
    func multiParameterSubscript() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Matrix {
                subscript(row: Int, column: Int) -> Double { get set }
            }
            """,
            expandedSource: """
            protocol Matrix {
                subscript(row: Int, column: Int) -> Double { get set }
            }

            #if DEBUG
            public class MatrixMock: Matrix {
                public var subscriptIntIntCallCount: Int = 0
                public var subscriptIntIntCallArgs: [(row: Int, column: Int)] = []
                public var subscriptIntIntHandler: (@Sendable ((row: Int, column: Int)) -> Double )? = nil
                public var subscriptIntIntSetHandler: (@Sendable ((row: Int, column: Int), Double ) -> Void)? = nil
                public subscript(row: Int, column: Int) -> Double {
                    get {
                        subscriptIntIntCallCount += 1
                        subscriptIntIntCallArgs.append((row: row, column: column))
                        guard let _handler = subscriptIntIntHandler else {
                            fatalError("\\(Self.self).subscriptIntIntHandler is not set")
                        }
                        return _handler((row: row, column: column))
                    }
                    set {
                        if let _handler = subscriptIntIntSetHandler {
                            _handler((row: row, column: column), newValue)
                        }
                    }
                }
                public func resetMock() {
                    subscriptIntIntCallCount = 0
                    subscriptIntIntCallArgs = []
                    subscriptIntIntHandler = nil
                    subscriptIntIntSetHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with multiple subscript overloads")
    func multipleSubscriptOverloads() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Collection {
                subscript(index: Int) -> String { get }
                subscript(key: String) -> Int { get set }
            }
            """,
            expandedSource: """
            protocol Collection {
                subscript(index: Int) -> String { get }
                subscript(key: String) -> Int { get set }
            }

            #if DEBUG
            public class CollectionMock: Collection {
                public var subscriptIntCallCount: Int = 0
                public var subscriptIntCallArgs: [Int] = []
                public var subscriptIntHandler: (@Sendable (Int) -> String )? = nil
                public subscript(index: Int) -> String {
                    subscriptIntCallCount += 1
                    subscriptIntCallArgs.append(index)
                    guard let _handler = subscriptIntHandler else {
                        fatalError("\\(Self.self).subscriptIntHandler is not set")
                    }
                    return _handler(index)
                }
                public var subscriptStringCallCount: Int = 0
                public var subscriptStringCallArgs: [String] = []
                public var subscriptStringHandler: (@Sendable (String) -> Int )? = nil
                public var subscriptStringSetHandler: (@Sendable (String, Int ) -> Void)? = nil
                public subscript(key: String) -> Int {
                    get {
                        subscriptStringCallCount += 1
                        subscriptStringCallArgs.append(key)
                        guard let _handler = subscriptStringHandler else {
                            fatalError("\\(Self.self).subscriptStringHandler is not set")
                        }
                        return _handler(key)
                    }
                    set {
                        if let _handler = subscriptStringSetHandler {
                            _handler(key, newValue)
                        }
                    }
                }
                public func resetMock() {
                    subscriptIntCallCount = 0
                    subscriptIntCallArgs = []
                    subscriptIntHandler = nil
                    subscriptStringCallCount = 0
                    subscriptStringCallArgs = []
                    subscriptStringHandler = nil
                    subscriptStringSetHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Sendable protocol with get-only subscript")
    func sendableGetOnlySubscript() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol SendableCache: Sendable {
                subscript(key: String) -> Int { get }
            }
            """,
            expandedSource: """
            protocol SendableCache: Sendable {
                subscript(key: String) -> Int { get }
            }

            #if DEBUG
            #if canImport(Synchronization)
            @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
            public final class SendableCacheMock: SendableCache, Sendable {
                private struct Storage {
                    var subscriptStringCallCount: Int = 0
                    var subscriptStringCallArgs: [String] = []
                    var subscriptStringHandler: (@Sendable (String) -> Int )? = nil
                }
                private let _storage = Mutex<Storage>(Storage())
                public var subscriptStringCallCount: Int {
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
                public var subscriptStringCallArgs: [String] {
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
                public var subscriptStringHandler: (@Sendable (String) -> Int )? {
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
                public subscript(key: String) -> Int {
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
                    return _handler(key)
                }
                public func resetMock() {
                    _storage.withLock { storage in
                        storage.subscriptStringCallCount = 0
                        storage.subscriptStringCallArgs = []
                        storage.subscriptStringHandler = nil
                    }
                }
            }
            #else
            public final class SendableCacheMock: SendableCache, Sendable {
                private struct Storage {
                    var subscriptStringCallCount: Int = 0
                    var subscriptStringCallArgs: [String] = []
                    var subscriptStringHandler: (@Sendable (String) -> Int )? = nil
                }
                private let _storage = LegacyLock<Storage>(Storage())
                public var subscriptStringCallCount: Int {
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
                public var subscriptStringCallArgs: [String] {
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
                public var subscriptStringHandler: (@Sendable (String) -> Int )? {
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
                public subscript(key: String) -> Int {
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
                    return _handler(key)
                }
                public func resetMock() {
                    _storage.withLock { storage in
                        storage.subscriptStringCallCount = 0
                        storage.subscriptStringCallArgs = []
                        storage.subscriptStringHandler = nil
                    }
                }
            }
            #endif
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Sendable protocol with get-set subscript")
    func sendableGetSetSubscript() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol SendableStorage: Sendable {
                subscript(index: Int) -> String { get set }
            }
            """,
            expandedSource: """
            protocol SendableStorage: Sendable {
                subscript(index: Int) -> String { get set }
            }

            #if DEBUG
            #if canImport(Synchronization)
            @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
            public final class SendableStorageMock: SendableStorage, Sendable {
                private struct Storage {
                    var subscriptIntCallCount: Int = 0
                    var subscriptIntCallArgs: [Int] = []
                    var subscriptIntHandler: (@Sendable (Int) -> String )? = nil
                    var subscriptIntSetHandler: (@Sendable (Int, String ) -> Void)? = nil
                }
                private let _storage = Mutex<Storage>(Storage())
                public var subscriptIntCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.subscriptIntCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptIntCallCount = newValue
                        }
                    }
                }
                public var subscriptIntCallArgs: [Int] {
                    get {
                        _storage.withLock {
                            $0.subscriptIntCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptIntCallArgs = newValue
                        }
                    }
                }
                public var subscriptIntHandler: (@Sendable (Int) -> String )? {
                    get {
                        _storage.withLock {
                            $0.subscriptIntHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptIntHandler = newValue
                        }
                    }
                }
                public var subscriptIntSetHandler: (@Sendable (Int, String ) -> Void)? {
                    get {
                        _storage.withLock {
                            $0.subscriptIntSetHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptIntSetHandler = newValue
                        }
                    }
                }
                public subscript(index: Int) -> String {
                    get {
                        _storage.withLock { storage in
                            storage.subscriptIntCallCount += 1
                            storage.subscriptIntCallArgs.append(index)
                        }
                        let _handler = _storage.withLock {
                            $0.subscriptIntHandler
                        }
                        guard let _handler else {
                            fatalError("\\(Self.self).subscriptIntHandler is not set")
                        }
                        return _handler(index)
                    }
                    set {
                        if let _handler = _storage.withLock({ $0.subscriptIntSetHandler
                            }) {
                            _handler(index, newValue)
                        }
                    }
                }
                public func resetMock() {
                    _storage.withLock { storage in
                        storage.subscriptIntCallCount = 0
                        storage.subscriptIntCallArgs = []
                        storage.subscriptIntHandler = nil
                        storage.subscriptIntSetHandler = nil
                    }
                }
            }
            #else
            public final class SendableStorageMock: SendableStorage, Sendable {
                private struct Storage {
                    var subscriptIntCallCount: Int = 0
                    var subscriptIntCallArgs: [Int] = []
                    var subscriptIntHandler: (@Sendable (Int) -> String )? = nil
                    var subscriptIntSetHandler: (@Sendable (Int, String ) -> Void)? = nil
                }
                private let _storage = LegacyLock<Storage>(Storage())
                public var subscriptIntCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.subscriptIntCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptIntCallCount = newValue
                        }
                    }
                }
                public var subscriptIntCallArgs: [Int] {
                    get {
                        _storage.withLock {
                            $0.subscriptIntCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptIntCallArgs = newValue
                        }
                    }
                }
                public var subscriptIntHandler: (@Sendable (Int) -> String )? {
                    get {
                        _storage.withLock {
                            $0.subscriptIntHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptIntHandler = newValue
                        }
                    }
                }
                public var subscriptIntSetHandler: (@Sendable (Int, String ) -> Void)? {
                    get {
                        _storage.withLock {
                            $0.subscriptIntSetHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptIntSetHandler = newValue
                        }
                    }
                }
                public subscript(index: Int) -> String {
                    get {
                        _storage.withLock { storage in
                            storage.subscriptIntCallCount += 1
                            storage.subscriptIntCallArgs.append(index)
                        }
                        let _handler = _storage.withLock {
                            $0.subscriptIntHandler
                        }
                        guard let _handler else {
                            fatalError("\\(Self.self).subscriptIntHandler is not set")
                        }
                        return _handler(index)
                    }
                    set {
                        if let _handler = _storage.withLock({ $0.subscriptIntSetHandler
                            }) {
                            _handler(index, newValue)
                        }
                    }
                }
                public func resetMock() {
                    _storage.withLock { storage in
                        storage.subscriptIntCallCount = 0
                        storage.subscriptIntCallArgs = []
                        storage.subscriptIntHandler = nil
                        storage.subscriptIntSetHandler = nil
                    }
                }
            }
            #endif
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Actor protocol with get-only subscript")
    func actorGetOnlySubscript() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol ActorCache: Actor {
                subscript(key: String) -> Int { get }
            }
            """,
            expandedSource: """
            protocol ActorCache: Actor {
                subscript(key: String) -> Int { get }
            }

            #if DEBUG
            #if canImport(Synchronization)
            @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
            public actor ActorCacheMock: ActorCache {
                private struct Storage {
                    var subscriptStringCallCount: Int = 0
                    var subscriptStringCallArgs: [String] = []
                    var subscriptStringHandler: (@Sendable (String) -> Int )? = nil
                }
                private let _storage = Mutex<Storage>(Storage())
                public nonisolated var subscriptStringCallCount: Int {
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
                public nonisolated var subscriptStringCallArgs: [String] {
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
                public nonisolated var subscriptStringHandler: (@Sendable (String) -> Int )? {
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
                public subscript(key: String) -> Int {
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
                    return _handler(key)
                }
                public nonisolated func resetMock() {
                    _storage.withLock { storage in
                        storage.subscriptStringCallCount = 0
                        storage.subscriptStringCallArgs = []
                        storage.subscriptStringHandler = nil
                    }
                }
            }
            #else
            public actor ActorCacheMock: ActorCache {
                private struct Storage {
                    var subscriptStringCallCount: Int = 0
                    var subscriptStringCallArgs: [String] = []
                    var subscriptStringHandler: (@Sendable (String) -> Int )? = nil
                }
                private let _storage = LegacyLock<Storage>(Storage())
                public nonisolated var subscriptStringCallCount: Int {
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
                public nonisolated var subscriptStringCallArgs: [String] {
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
                public nonisolated var subscriptStringHandler: (@Sendable (String) -> Int )? {
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
                public subscript(key: String) -> Int {
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
                    return _handler(key)
                }
                public nonisolated func resetMock() {
                    _storage.withLock { storage in
                        storage.subscriptStringCallCount = 0
                        storage.subscriptStringCallArgs = []
                        storage.subscriptStringHandler = nil
                    }
                }
            }
            #endif
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Actor protocol with get-set subscript")
    func actorGetSetSubscript() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol ActorStorage: Actor {
                subscript(index: Int) -> String { get set }
            }
            """,
            expandedSource: """
            protocol ActorStorage: Actor {
                subscript(index: Int) -> String { get set }
            }

            #if DEBUG
            #if canImport(Synchronization)
            @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
            public actor ActorStorageMock: ActorStorage {
                private struct Storage {
                    var subscriptIntCallCount: Int = 0
                    var subscriptIntCallArgs: [Int] = []
                    var subscriptIntHandler: (@Sendable (Int) -> String )? = nil
                    var subscriptIntSetHandler: (@Sendable (Int, String ) -> Void)? = nil
                }
                private let _storage = Mutex<Storage>(Storage())
                public nonisolated var subscriptIntCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.subscriptIntCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptIntCallCount = newValue
                        }
                    }
                }
                public nonisolated var subscriptIntCallArgs: [Int] {
                    get {
                        _storage.withLock {
                            $0.subscriptIntCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptIntCallArgs = newValue
                        }
                    }
                }
                public nonisolated var subscriptIntHandler: (@Sendable (Int) -> String )? {
                    get {
                        _storage.withLock {
                            $0.subscriptIntHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptIntHandler = newValue
                        }
                    }
                }
                public nonisolated var subscriptIntSetHandler: (@Sendable (Int, String ) -> Void)? {
                    get {
                        _storage.withLock {
                            $0.subscriptIntSetHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptIntSetHandler = newValue
                        }
                    }
                }
                public subscript(index: Int) -> String {
                    get {
                        _storage.withLock { storage in
                            storage.subscriptIntCallCount += 1
                            storage.subscriptIntCallArgs.append(index)
                        }
                        let _handler = _storage.withLock {
                            $0.subscriptIntHandler
                        }
                        guard let _handler else {
                            fatalError("\\(Self.self).subscriptIntHandler is not set")
                        }
                        return _handler(index)
                    }
                    set {
                        if let _handler = _storage.withLock({ $0.subscriptIntSetHandler
                            }) {
                            _handler(index, newValue)
                        }
                    }
                }
                public nonisolated func resetMock() {
                    _storage.withLock { storage in
                        storage.subscriptIntCallCount = 0
                        storage.subscriptIntCallArgs = []
                        storage.subscriptIntHandler = nil
                        storage.subscriptIntSetHandler = nil
                    }
                }
            }
            #else
            public actor ActorStorageMock: ActorStorage {
                private struct Storage {
                    var subscriptIntCallCount: Int = 0
                    var subscriptIntCallArgs: [Int] = []
                    var subscriptIntHandler: (@Sendable (Int) -> String )? = nil
                    var subscriptIntSetHandler: (@Sendable (Int, String ) -> Void)? = nil
                }
                private let _storage = LegacyLock<Storage>(Storage())
                public nonisolated var subscriptIntCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.subscriptIntCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptIntCallCount = newValue
                        }
                    }
                }
                public nonisolated var subscriptIntCallArgs: [Int] {
                    get {
                        _storage.withLock {
                            $0.subscriptIntCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptIntCallArgs = newValue
                        }
                    }
                }
                public nonisolated var subscriptIntHandler: (@Sendable (Int) -> String )? {
                    get {
                        _storage.withLock {
                            $0.subscriptIntHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptIntHandler = newValue
                        }
                    }
                }
                public nonisolated var subscriptIntSetHandler: (@Sendable (Int, String ) -> Void)? {
                    get {
                        _storage.withLock {
                            $0.subscriptIntSetHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.subscriptIntSetHandler = newValue
                        }
                    }
                }
                public subscript(index: Int) -> String {
                    get {
                        _storage.withLock { storage in
                            storage.subscriptIntCallCount += 1
                            storage.subscriptIntCallArgs.append(index)
                        }
                        let _handler = _storage.withLock {
                            $0.subscriptIntHandler
                        }
                        guard let _handler else {
                            fatalError("\\(Self.self).subscriptIntHandler is not set")
                        }
                        return _handler(index)
                    }
                    set {
                        if let _handler = _storage.withLock({ $0.subscriptIntSetHandler
                            }) {
                            _handler(index, newValue)
                        }
                    }
                }
                public nonisolated func resetMock() {
                    _storage.withLock { storage in
                        storage.subscriptIntCallCount = 0
                        storage.subscriptIntCallArgs = []
                        storage.subscriptIntHandler = nil
                        storage.subscriptIntSetHandler = nil
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
