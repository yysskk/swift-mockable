import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import MockableMacros

/// A requirement returning nothing takes the no-return-value path — an unset handler is
/// a no-op rather than a trap — however its `Void` return is spelled.
@Suite("Void Return Macro Tests")
struct VoidReturnMacroTests {
    let testMacros: [String: Macro.Type] = [
        "Mockable": MockableMacro.self
    ]

    @Test("A qualified or parenthesized Void return is mocked like a bare one")
    func voidSpellings() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Service {
                func qualified() -> Swift.Void
                func parenthesized() -> (Void)
            }
            """,
            expandedSource: """
            protocol Service {
                func qualified() -> Swift.Void
                func parenthesized() -> (Void)
            }

            #if DEBUG
            class ServiceMock: Service {
                var qualifiedCallCount: Int = 0
                var qualifiedCallArgs: [()] = []
                var qualifiedHandler: (@Sendable () -> Swift.Void)? = nil
                func qualified() -> Swift.Void {
                    qualifiedCallCount += 1
                    qualifiedCallArgs.append(())
                    if let _handler = qualifiedHandler {
                        _handler()
                    }
                }
                var parenthesizedCallCount: Int = 0
                var parenthesizedCallArgs: [()] = []
                var parenthesizedHandler: (@Sendable () -> Void)? = nil
                func parenthesized() -> (Void) {
                    parenthesizedCallCount += 1
                    parenthesizedCallArgs.append(())
                    if let _handler = parenthesizedHandler {
                        _handler()
                    }
                }
                func resetMock() {
                    qualifiedCallCount = 0
                    qualifiedCallArgs = []
                    qualifiedHandler = nil
                    parenthesizedCallCount = 0
                    parenthesizedCallArgs = []
                    parenthesizedHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("A Void return contributes no overload suffix, however it is spelled")
    func voidReturnIsNotADisambiguator() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Service {
                func run() -> Swift.Void
                func run() -> Int
            }
            """,
            expandedSource: """
            protocol Service {
                func run() -> Swift.Void
                func run() -> Int
            }

            #if DEBUG
            class ServiceMock: Service {
                var runCallCount: Int = 0
                var runCallArgs: [()] = []
                var runHandler: (@Sendable () -> Swift.Void)? = nil
                func run() -> Swift.Void {
                    runCallCount += 1
                    runCallArgs.append(())
                    if let _handler = runHandler {
                        _handler()
                    }
                }
                var runIntCallCount: Int = 0
                var runIntCallArgs: [()] = []
                var runIntHandler: (@Sendable () -> Int)? = nil
                func run() -> Int {
                    runIntCallCount += 1
                    runIntCallArgs.append(())
                    guard let _handler = runIntHandler else {
                        fatalError("\\(Self.self).runIntHandler is not set")
                    }
                    return _handler()
                }
                func resetMock() {
                    runCallCount = 0
                    runCallArgs = []
                    runHandler = nil
                    runIntCallCount = 0
                    runIntCallArgs = []
                    runIntHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }
}
