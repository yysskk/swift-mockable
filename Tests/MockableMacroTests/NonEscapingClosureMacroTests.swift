import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import MockableMacros

@Suite("Non-Escaping Closure Macro Tests")
struct NonEscapingClosureMacroTests {
    private let testMacros: [String: Macro.Type] = [
        "Mockable": MockableMacro.self
    ]

    @Test("Non-escaping closure parameter is excluded from CallArguments but forwarded to the handler")
    func nonEscapingClosureExcludedFromCallArguments() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Runner {
                func run(_ body: () -> Void)
            }
            """,
            expandedSource: """
            protocol Runner {
                func run(_ body: () -> Void)
            }

            #if DEBUG
            class RunnerMock: Runner {
                private(set) var runCallCount: Int = 0
                private(set) var runCallArguments: [()] = []
                var runHandler: ((() -> Void) -> Void)? = nil
                func run(_ body: () -> Void) {
                    runCallCount += 1
                    runCallArguments.append(())
                    if let _handler = runHandler {
                        _handler(body)
                    }
                }
                func resetMock() {
                    runCallCount = 0
                    runCallArguments = []
                    runHandler = nil
                }
                class func resetMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Storable parameters are recorded while the non-escaping closure is only forwarded")
    func mixedParametersRecordOnlyStorableValues() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Executor {
                func run(label: String, _ body: () -> Void) -> Int
            }
            """,
            expandedSource: """
            protocol Executor {
                func run(label: String, _ body: () -> Void) -> Int
            }

            #if DEBUG
            class ExecutorMock: Executor {
                private(set) var runCallCount: Int = 0
                private(set) var runCallArguments: [String] = []
                var runHandler: ((String, () -> Void) -> Int)? = nil
                func run(label: String, _ body: () -> Void) -> Int {
                    runCallCount += 1
                    runCallArguments.append(label)
                    guard let _handler = runHandler else {
                        fatalError("\\(Self.self).runHandler is not set")
                    }
                    return _handler(label, body)
                }
                func resetMock() {
                    runCallCount = 0
                    runCallArguments = []
                    runHandler = nil
                }
                class func resetMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Escaping closure parameters are still recorded in CallArguments")
    func escapingClosureStillRecorded() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Subscriber {
                func subscribe(_ handler: @escaping (Int) -> Void)
            }
            """,
            expandedSource: """
            protocol Subscriber {
                func subscribe(_ handler: @escaping (Int) -> Void)
            }

            #if DEBUG
            class SubscriberMock: Subscriber {
                private(set) var subscribeCallCount: Int = 0
                private(set) var subscribeCallArguments: [(Int) -> Void] = []
                var subscribeHandler: (((Int) -> Void) -> Void)? = nil
                func subscribe(_ handler: @escaping (Int) -> Void) {
                    subscribeCallCount += 1
                    subscribeCallArguments.append(handler)
                    if let _handler = subscribeHandler {
                        _handler(handler)
                    }
                }
                func resetMock() {
                    subscribeCallCount = 0
                    subscribeCallArguments = []
                    subscribeHandler = nil
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
