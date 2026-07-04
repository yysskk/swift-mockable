import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import MockableMacros

@Suite("Diagnostics Macro Tests")
struct DiagnosticsMacroTests {
    private let testMacros: [String: Macro.Type] = [
        "Mockable": MockableMacro.self
    ]

    @Test("rethrows requirement should produce a diagnostic")
    func rethrowsRequirementProducesDiagnostic() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Runner {
                func run(_ body: () throws -> Void) rethrows
            }
            """,
            expandedSource: """
            protocol Runner {
                func run(_ body: () throws -> Void) rethrows
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'rethrows' requirements are not supported by @Mockable; declare the requirement as 'throws' instead",
                    line: 3,
                    column: 5
                )
            ],
            macros: testMacros
        )
    }

    @Test("rethrows requirement with a return value should produce a diagnostic")
    func rethrowsRequirementWithReturnValueProducesDiagnostic() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Transformer {
                func transform(_ body: (Int) throws -> Int) rethrows -> Int
            }
            """,
            expandedSource: """
            protocol Transformer {
                func transform(_ body: (Int) throws -> Int) rethrows -> Int
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'rethrows' requirements are not supported by @Mockable; declare the requirement as 'throws' instead",
                    line: 3,
                    column: 5
                )
            ],
            macros: testMacros
        )
    }

    @Test("rethrows requirement inside #if should produce a diagnostic")
    func rethrowsRequirementInsideConditionalProducesDiagnostic() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Worker {
                #if os(macOS)
                func perform(_ body: () throws -> Void) rethrows
                #endif
            }
            """,
            expandedSource: """
            protocol Worker {
                #if os(macOS)
                func perform(_ body: () throws -> Void) rethrows
                #endif
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'rethrows' requirements are not supported by @Mockable; declare the requirement as 'throws' instead",
                    line: 4,
                    column: 5
                )
            ],
            macros: testMacros
        )
    }

    @Test("throws requirement taking a throwing closure is still supported")
    func throwsRequirementWithThrowingClosureParameterExpands() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Executor {
                func execute(_ body: @escaping () throws -> Void) throws
            }
            """,
            expandedSource: """
            protocol Executor {
                func execute(_ body: @escaping () throws -> Void) throws
            }

            #if DEBUG
            class ExecutorMock: Executor {
                var executeCallCount: Int = 0
                var executeCallArgs: [() throws -> Void] = []
                var executeHandler: (@Sendable (() throws -> Void) throws -> Void)? = nil
                func execute(_ body: @escaping () throws -> Void) throws {
                    executeCallCount += 1
                    executeCallArgs.append(body)
                    if let _handler = executeHandler {
                        try _handler(body)
                    }
                }
                func resetMock() {
                    executeCallCount = 0
                    executeCallArgs = []
                    executeHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }
}
