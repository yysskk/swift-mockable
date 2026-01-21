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
                    guard let handler = fetchUserHandler else {
                        fatalError("\\(Self.self).fetchUserHandler is not set")
                    }
                    return handler(id)
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
                    guard let handler = loadDataHandler else {
                        fatalError("\\(Self.self).loadDataHandler is not set")
                    }
                    return try await handler(url)
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
                    guard let handler = addHandler else {
                        fatalError("\\(Self.self).addHandler is not set")
                    }
                    return handler((a: a, b: b))
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
                    if let handler = logHandler {
                        handler(message)
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
                    guard let handler = getHandler else {
                        fatalError("\\(Self.self).getHandler is not set")
                    }
                    return handler(key) as! T
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
                    if let handler = saveHandler {
                        handler((value: value, key: key))
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
                    guard let handler = getHandler else {
                        fatalError("\\(Self.self).getHandler is not set")
                    }
                    return handler(key) as! T
                }
                public var setCallCount: Int = 0
                public var setCallArgs: [(value: Any, key: Any)] = []
                public var setHandler: (@Sendable ((value: Any, key: Any)) -> Void)?
                public func set<T>(_ value: T, forKey key: UserDefaultsKey<T>) {
                    setCallCount += 1
                    setCallArgs.append((value: value, key: key))
                    if let handler = setHandler {
                        handler((value: value, key: key))
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
                    guard let handler = integerHandler else {
                        fatalError("\\(Self.self).integerHandler is not set")
                    }
                    return handler(key)
                }
                public var setIntegerCallCount: Int = 0
                public var setIntegerCallArgs: [(value: Int, key: UserDefaultsKey<Int>)] = []
                public var setIntegerHandler: (@Sendable ((value: Int, key: UserDefaultsKey<Int>)) -> Void)?
                public func setInteger(_ value: Int, forKey key: UserDefaultsKey<Int>) {
                    setIntegerCallCount += 1
                    setIntegerCallArgs.append((value: value, key: key))
                    if let handler = setIntegerHandler {
                        handler((value: value, key: key))
                    }
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }
}
