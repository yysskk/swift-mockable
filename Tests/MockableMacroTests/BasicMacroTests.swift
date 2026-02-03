import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import MockableMacros

@Suite("Basic Macro Tests")
struct BasicMacroTests {
    private let testMacros: [String: Macro.Type] = [
        "Mockable": MockableMacro.self
    ]

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
                func subscribe(handler: @escaping @Sendable (String) -> Void)
            }
            """,
            expandedSource: """
            protocol EventHandler {
                func subscribe(handler: @escaping @Sendable (String) -> Void)
            }

            #if DEBUG
            public class EventHandlerMock: EventHandler {
                public var subscribeCallCount: Int = 0
                public var subscribeCallArgs: [@Sendable (String) -> Void] = []
                public var subscribeHandler: (@Sendable (@Sendable (String) -> Void) -> Void)? = nil
                public func subscribe(handler: @escaping @Sendable (String) -> Void) {
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
}
