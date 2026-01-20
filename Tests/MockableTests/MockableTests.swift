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
                public var theme: String!
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
}
