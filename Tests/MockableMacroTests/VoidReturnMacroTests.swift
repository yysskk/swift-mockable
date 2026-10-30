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
                private(set) var qualifiedCallCount: Int = 0
                private(set) var qualifiedCallArguments: [()] = []
                var qualifiedHandler: (() -> Swift.Void)? = nil
                func qualified() -> Swift.Void {
                    qualifiedCallCount += 1
                    qualifiedCallArguments.append(())
                    if let _handler = qualifiedHandler {
                        _handler()
                    }
                }
                private(set) var parenthesizedCallCount: Int = 0
                private(set) var parenthesizedCallArguments: [()] = []
                var parenthesizedHandler: (() -> Void)? = nil
                func parenthesized() -> (Void) {
                    parenthesizedCallCount += 1
                    parenthesizedCallArguments.append(())
                    if let _handler = parenthesizedHandler {
                        _handler()
                    }
                }
                func resetMock() {
                    qualifiedCallCount = 0
                    qualifiedCallArguments = []
                    qualifiedHandler = nil
                    parenthesizedCallCount = 0
                    parenthesizedCallArguments = []
                    parenthesizedHandler = nil
                }
                class func resetMock() {
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
                private(set) var runCallCount: Int = 0
                private(set) var runCallArguments: [()] = []
                var runHandler: (() -> Swift.Void)? = nil
                func run() -> Swift.Void {
                    runCallCount += 1
                    runCallArguments.append(())
                    if let _handler = runHandler {
                        _handler()
                    }
                }
                private(set) var runIntCallCount: Int = 0
                private(set) var runIntCallArguments: [()] = []
                var runIntHandler: (() -> Int)? = nil
                func run() -> Int {
                    runIntCallCount += 1
                    runIntCallArguments.append(())
                    guard let _handler = runIntHandler else {
                        fatalError("\\(Self.self).runIntHandler is not set")
                    }
                    return _handler()
                }
                func resetMock() {
                    runCallCount = 0
                    runCallArguments = []
                    runHandler = nil
                    runIntCallCount = 0
                    runIntCallArguments = []
                    runIntHandler = nil
                }
                class func resetMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }
}
