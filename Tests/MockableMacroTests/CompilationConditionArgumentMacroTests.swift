import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import MockableMacros

@Suite("Compilation Condition Argument Macro Tests")
struct CompilationConditionArgumentMacroTests {
    private let testMacros: [String: Macro.Type] = [
        "Mockable": MockableMacro.self
    ]

    @Test("Explicit .debug matches the default #if DEBUG guard")
    func explicitDebugCondition() {
        assertMacroExpansionForTesting(
            """
            @Mockable(condition: .debug)
            protocol UserService {
                func fetchUser(id: Int) -> String
            }
            """,
            expandedSource: """
            protocol UserService {
                func fetchUser(id: Int) -> String
            }

            #if DEBUG
            class UserServiceMock: UserService {
                var fetchUserCallCount: Int = 0
                var fetchUserCallArgs: [Int] = []
                var fetchUserHandler: (@Sendable (Int) -> String)? = nil
                func fetchUser(id: Int) -> String {
                    fetchUserCallCount += 1
                    fetchUserCallArgs.append(id)
                    guard let _handler = fetchUserHandler else {
                        fatalError("\\(Self.self).fetchUserHandler is not set")
                    }
                    return _handler(id)
                }
                func resetMock() {
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

    @Test(".always emits the mock without an #if guard")
    func alwaysCondition() {
        assertMacroExpansionForTesting(
            """
            @Mockable(condition: .always)
            protocol UserService {
                func fetchUser(id: Int) -> String
            }
            """,
            expandedSource: """
            protocol UserService {
                func fetchUser(id: Int) -> String
            }

            class UserServiceMock: UserService {
                var fetchUserCallCount: Int = 0
                var fetchUserCallArgs: [Int] = []
                var fetchUserHandler: (@Sendable (Int) -> String)? = nil
                func fetchUser(id: Int) -> String {
                    fetchUserCallCount += 1
                    fetchUserCallArgs.append(id)
                    guard let _handler = fetchUserHandler else {
                        fatalError("\\(Self.self).fetchUserHandler is not set")
                    }
                    return _handler(id)
                }
                func resetMock() {
                    fetchUserCallCount = 0
                    fetchUserCallArgs = []
                    fetchUserHandler = nil
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test(".custom wraps the mock in the custom flag")
    func customCondition() {
        assertMacroExpansionForTesting(
            """
            @Mockable(condition: .custom("MOCKING"))
            protocol UserService {
                func fetchUser(id: Int) -> String
            }
            """,
            expandedSource: """
            protocol UserService {
                func fetchUser(id: Int) -> String
            }

            #if MOCKING
            class UserServiceMock: UserService {
                var fetchUserCallCount: Int = 0
                var fetchUserCallArgs: [Int] = []
                var fetchUserHandler: (@Sendable (Int) -> String)? = nil
                func fetchUser(id: Int) -> String {
                    fetchUserCallCount += 1
                    fetchUserCallArgs.append(id)
                    guard let _handler = fetchUserHandler else {
                        fatalError("\\(Self.self).fetchUserHandler is not set")
                    }
                    return _handler(id)
                }
                func resetMock() {
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

    @Test(".custom accepts flags with underscores and digits")
    func customConditionWithUnderscoresAndDigits() {
        assertMacroExpansionForTesting(
            """
            @Mockable(condition: .custom("_ENABLE_MOCKS_2"))
            protocol CacheService {
                func clear()
            }
            """,
            expandedSource: """
            protocol CacheService {
                func clear()
            }

            #if _ENABLE_MOCKS_2
            class CacheServiceMock: CacheService {
                var clearCallCount: Int = 0
                var clearCallArgs: [()] = []
                var clearHandler: (@Sendable () -> Void)? = nil
                func clear() {
                    clearCallCount += 1
                    clearCallArgs.append(())
                    if let _handler = clearHandler {
                        _handler()
                    }
                }
                func resetMock() {
                    clearCallCount = 0
                    clearCallArgs = []
                    clearHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test(
        ".custom accepts compilation condition expressions",
        arguments: [
            "DEBUG || MOCKING",
            "!RELEASE",
            "os(iOS) && DEBUG",
            "(DEBUG || STAGING) && !SKIP_MOCKS",
            "canImport(XCTest)",
            "swift(>=6.0)",
            "targetEnvironment(simulator)",
            "true",
        ]
    )
    func customConditionExpressions(expression: String) {
        assertMacroExpansionForTesting(
            """
            @Mockable(condition: .custom("\(expression)"))
            protocol CacheService {
                func clear()
            }
            """,
            expandedSource: """
            protocol CacheService {
                func clear()
            }

            #if \(expression)
            class CacheServiceMock: CacheService {
                var clearCallCount: Int = 0
                var clearCallArgs: [()] = []
                var clearHandler: (@Sendable () -> Void)? = nil
                func clear() {
                    clearCallCount += 1
                    clearCallArgs.append(())
                    if let _handler = clearHandler {
                        _handler()
                    }
                }
                func resetMock() {
                    clearCallCount = 0
                    clearCallArgs = []
                    clearHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test(".custom trims surrounding whitespace from the condition")
    func customConditionTrimsWhitespace() {
        assertMacroExpansionForTesting(
            """
            @Mockable(condition: .custom("  DEBUG  "))
            protocol CacheService {
                func clear()
            }
            """,
            expandedSource: """
            protocol CacheService {
                func clear()
            }

            #if DEBUG
            class CacheServiceMock: CacheService {
                var clearCallCount: Int = 0
                var clearCallArgs: [()] = []
                var clearHandler: (@Sendable () -> Void)? = nil
                func clear() {
                    clearCallCount += 1
                    clearCallArgs.append(())
                    if let _handler = clearHandler {
                        _handler()
                    }
                }
                func resetMock() {
                    clearCallCount = 0
                    clearCallArgs = []
                    clearHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Type-qualified condition value is accepted")
    func typeQualifiedCondition() {
        assertMacroExpansionForTesting(
            """
            @Mockable(condition: MockCompilationCondition.always)
            protocol PingService {
                func ping() -> Bool
            }
            """,
            expandedSource: """
            protocol PingService {
                func ping() -> Bool
            }

            class PingServiceMock: PingService {
                var pingCallCount: Int = 0
                var pingCallArgs: [()] = []
                var pingHandler: (@Sendable () -> Bool)? = nil
                func ping() -> Bool {
                    pingCallCount += 1
                    pingCallArgs.append(())
                    guard let _handler = pingHandler else {
                        fatalError("\\(Self.self).pingHandler is not set")
                    }
                    return _handler()
                }
                func resetMock() {
                    pingCallCount = 0
                    pingCallArgs = []
                    pingHandler = nil
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test("Public protocol with .always keeps access-level handling")
    func publicProtocolWithAlwaysCondition() {
        assertMacroExpansionForTesting(
            """
            @Mockable(condition: .always)
            public protocol PublicService {
                func fetch() -> String
            }
            """,
            expandedSource: """
            public protocol PublicService {
                func fetch() -> String
            }

            open class PublicServiceMock: PublicService {
                public init() {
                }
                public var fetchCallCount: Int = 0
                public var fetchCallArgs: [()] = []
                public var fetchHandler: (@Sendable () -> String)? = nil
                public func fetch() -> String {
                    fetchCallCount += 1
                    fetchCallArgs.append(())
                    guard let _handler = fetchHandler else {
                        fatalError("\\(Self.self).fetchHandler is not set")
                    }
                    return _handler()
                }
                open func resetMock() {
                    fetchCallCount = 0
                    fetchCallArgs = []
                    fetchHandler = nil
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test("Empty argument list defaults to #if DEBUG")
    func emptyArgumentListDefaultsToDebug() {
        assertMacroExpansionForTesting(
            """
            @Mockable()
            protocol PingService {
                func ping()
            }
            """,
            expandedSource: """
            protocol PingService {
                func ping()
            }

            #if DEBUG
            class PingServiceMock: PingService {
                var pingCallCount: Int = 0
                var pingCallArgs: [()] = []
                var pingHandler: (@Sendable () -> Void)? = nil
                func ping() {
                    pingCallCount += 1
                    pingCallArgs.append(())
                    if let _handler = pingHandler {
                        _handler()
                    }
                }
                func resetMock() {
                    pingCallCount = 0
                    pingCallArgs = []
                    pingHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    // MARK: - Diagnostics

    @Test("Unlabeled argument produces a diagnostic")
    func unlabeledArgumentProducesDiagnostic() {
        assertMacroExpansionForTesting(
            """
            @Mockable(.always)
            protocol CacheService {
                func clear()
            }
            """,
            expandedSource: """
            protocol CacheService {
                func clear()
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Invalid @Mockable argument: @Mockable does not accept unlabeled arguments; the only supported argument is 'condition:'",
                    line: 1,
                    column: 11
                )
            ],
            macros: testMacros
        )
    }

    @Test("Unknown argument label produces a diagnostic")
    func unknownArgumentLabelProducesDiagnostic() {
        assertMacroExpansionForTesting(
            """
            @Mockable(flag: "MOCKING")
            protocol CacheService {
                func clear()
            }
            """,
            expandedSource: """
            protocol CacheService {
                func clear()
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Invalid @Mockable argument: unexpected argument label 'flag'; the only supported argument is 'condition:'",
                    line: 1,
                    column: 11
                )
            ],
            macros: testMacros
        )
    }

    @Test("Duplicate condition argument produces a diagnostic")
    func duplicateConditionProducesDiagnostic() {
        assertMacroExpansionForTesting(
            """
            @Mockable(condition: .debug, condition: .always)
            protocol CacheService {
                func clear()
            }
            """,
            expandedSource: """
            protocol CacheService {
                func clear()
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Invalid @Mockable argument: duplicate 'condition' argument",
                    line: 1,
                    column: 30
                )
            ],
            macros: testMacros
        )
    }

    @Test("Non-literal condition value produces a diagnostic")
    func nonLiteralConditionProducesDiagnostic() {
        assertMacroExpansionForTesting(
            """
            @Mockable(condition: someCondition)
            protocol CacheService {
                func clear()
            }
            """,
            expandedSource: """
            protocol CacheService {
                func clear()
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Invalid @Mockable argument: the 'condition' argument must be written literally as '.debug', '.always', or '.custom(\"CONDITION\")'",
                    line: 1,
                    column: 22
                )
            ],
            macros: testMacros
        )
    }

    @Test("Unknown condition case produces a diagnostic")
    func unknownConditionCaseProducesDiagnostic() {
        assertMacroExpansionForTesting(
            """
            @Mockable(condition: .release)
            protocol CacheService {
                func clear()
            }
            """,
            expandedSource: """
            protocol CacheService {
                func clear()
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Invalid @Mockable argument: the 'condition' argument must be written literally as '.debug', '.always', or '.custom(\"CONDITION\")'",
                    line: 1,
                    column: 22
                )
            ],
            macros: testMacros
        )
    }

    @Test(".custom with a non-literal argument produces a diagnostic")
    func customWithNonLiteralArgumentProducesDiagnostic() {
        assertMacroExpansionForTesting(
            """
            @Mockable(condition: .custom(flagVariable))
            protocol CacheService {
                func clear()
            }
            """,
            expandedSource: """
            protocol CacheService {
                func clear()
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Invalid @Mockable argument: '.custom' requires a single string literal, e.g. '.custom(\"MOCKING\")'",
                    line: 1,
                    column: 22
                )
            ],
            macros: testMacros
        )
    }

    @Test(".custom with string interpolation produces a diagnostic")
    func customWithInterpolationProducesDiagnostic() {
        assertMacroExpansionForTesting(
            #"""
            @Mockable(condition: .custom("\(flag)"))
            protocol CacheService {
                func clear()
            }
            """#,
            expandedSource: """
            protocol CacheService {
                func clear()
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Invalid @Mockable argument: the custom compilation condition must be a string literal without interpolation",
                    line: 1,
                    column: 30
                )
            ],
            macros: testMacros
        )
    }

    @Test(".custom with an empty flag produces a diagnostic")
    func customWithEmptyFlagProducesDiagnostic() {
        assertMacroExpansionForTesting(
            """
            @Mockable(condition: .custom(""))
            protocol CacheService {
                func clear()
            }
            """,
            expandedSource: """
            protocol CacheService {
                func clear()
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Invalid @Mockable argument: the custom compilation condition must not be empty",
                    line: 1,
                    column: 30
                )
            ],
            macros: testMacros
        )
    }

    @Test(".custom with a flag starting with a digit produces a diagnostic")
    func customWithLeadingDigitProducesDiagnostic() {
        assertMacroExpansionForTesting(
            """
            @Mockable(condition: .custom("1MOCKING"))
            protocol CacheService {
                func clear()
            }
            """,
            expandedSource: """
            protocol CacheService {
                func clear()
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Invalid @Mockable argument: '1MOCKING' is not a valid compilation condition expression",
                    line: 1,
                    column: 30
                )
            ],
            macros: testMacros
        )
    }

    @Test(".custom with a malformed expression produces a diagnostic")
    func customWithMalformedExpressionProducesDiagnostic() {
        assertMacroExpansionForTesting(
            """
            @Mockable(condition: .custom("DEBUG ||"))
            protocol CacheService {
                func clear()
            }
            """,
            expandedSource: """
            protocol CacheService {
                func clear()
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Invalid @Mockable argument: 'DEBUG ||' is not a valid compilation condition expression",
                    line: 1,
                    column: 30
                )
            ],
            macros: testMacros
        )
    }

    @Test(
        ".custom with an unsupported construct produces a diagnostic",
        arguments: [
            "1 + 1",
            "A ? B : C",
            "unknownCheck(iOS)",
            "A & B",
            "Configuration.debug",
        ]
    )
    func customWithUnsupportedConstructProducesDiagnostic(expression: String) {
        assertMacroExpansionForTesting(
            """
            @Mockable(condition: .custom("\(expression)"))
            protocol CacheService {
                func clear()
            }
            """,
            expandedSource: """
            protocol CacheService {
                func clear()
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Invalid @Mockable argument: '\(expression)' is not a supported compilation condition; "
                        + "use identifiers, 'true'/'false', '!', '&&', '||', parentheses, and platform checks "
                        + "such as 'os(iOS)', 'canImport(UIKit)', or 'swift(>=6.0)'",
                    line: 1,
                    column: 30
                )
            ],
            macros: testMacros
        )
    }

    @Test("Invalid condition does not suppress member diagnostics")
    func invalidConditionAndUnsupportedMemberBothDiagnose() {
        assertMacroExpansionForTesting(
            """
            @Mockable(condition: .release)
            protocol StorageService {
                static subscript(index: Int) -> String { get }
            }
            """,
            expandedSource: """
            protocol StorageService {
                static subscript(index: Int) -> String { get }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Invalid @Mockable argument: the 'condition' argument must be written literally as '.debug', '.always', or '.custom(\"CONDITION\")'",
                    line: 1,
                    column: 22
                ),
                DiagnosticSpec(
                    message: "Unsupported protocol member: static subscript(index: Int) -> String { get }",
                    line: 3,
                    column: 5
                )
            ],
            macros: testMacros
        )
    }
}
