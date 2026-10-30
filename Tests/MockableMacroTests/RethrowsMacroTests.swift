import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import MockableMacros

@Suite("Rethrows Macro Tests")
struct RethrowsMacroTests {
    private let testMacros: [String: Macro.Type] = [
        "Mockable": MockableMacro.self
    ]

    @Test("rethrows requirement generates a non-throwing handler")
    func rethrowsRequirementGeneratesNonThrowingHandler() {
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

            #if DEBUG
            class RunnerMock: Runner {
                private(set) var runCallCount: Int = 0
                @available(*, deprecated, message: "run records no arguments; use runCallCount instead.")
                var runCallArguments: [()] {
                    Array(repeating: (), count: runCallCount)
                }
                var runHandler: ((() throws -> Void) -> Void)? = nil
                func run(_ body: () throws -> Void) rethrows {
                    runCallCount += 1
                    if let _handler = runHandler {
                        _handler(body)
                    }
                }
                func resetMock() {
                    runCallCount = 0
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

    @Test("rethrows requirement with a return value generates a non-throwing handler")
    func rethrowsRequirementWithReturnValueGeneratesNonThrowingHandler() {
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

            #if DEBUG
            class TransformerMock: Transformer {
                private(set) var transformCallCount: Int = 0
                @available(*, deprecated, message: "transform records no arguments; use transformCallCount instead.")
                var transformCallArguments: [()] {
                    Array(repeating: (), count: transformCallCount)
                }
                var transformHandler: (((Int) throws -> Int) -> Int)? = nil
                func transform(_ body: (Int) throws -> Int) rethrows -> Int {
                    transformCallCount += 1
                    guard let _handler = transformHandler else {
                        fatalError("\\(Self.self).transformHandler is not set")
                    }
                    return _handler(body)
                }
                func resetMock() {
                    transformCallCount = 0
                    transformHandler = nil
                }
                class func resetMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Sendable rethrows requirement stores a non-throwing handler")
    func sendableRethrowsRequirement() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Runner: Sendable {
                func run(_ body: @Sendable () throws -> Void) rethrows
            }
            """,
            expandedSource: """
            protocol Runner: Sendable {
                func run(_ body: @Sendable () throws -> Void) rethrows
            }

            #if DEBUG
            class RunnerMock: Runner, @unchecked Sendable {
                private struct Storage {
                    var runCallCount: Int = 0
                    var runHandler: (@Sendable (@Sendable () throws -> Void) -> Void)? = nil
                }
                private let _storage = MockableLock<Storage>(Storage())
                var runCallCount: Int {
                    _storage.withLock {
                        $0.runCallCount
                    }
                }
                @available(*, deprecated, message: "run records no arguments; use runCallCount instead.")
                var runCallArguments: [()] {
                    Array(repeating: (), count: runCallCount)
                }
                var runHandler: (@Sendable (@Sendable () throws -> Void) -> Void)? {
                    get {
                        _storage.withLock {
                            $0.runHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.runHandler = newValue
                        }
                    }
                }
                func run(_ body: @Sendable () throws -> Void) rethrows {
                    let _handler = _storage.withLock { storage -> (@Sendable (@Sendable () throws -> Void) -> Void)? in
                        storage.runCallCount += 1
                        return storage.runHandler
                    }
                    if let _handler {
                        _handler(body)
                    }
                }
                func resetMock() {
                    _storage.withLock { storage in
                        storage.runCallCount = 0
                        storage.runHandler = nil
                    }
                }
                class func resetMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("throws requirement taking a throwing closure keeps a throwing handler")
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
                private(set) var executeCallCount: Int = 0
                private(set) var executeCallArguments: [() throws -> Void] = []
                var executeHandler: ((() throws -> Void) throws -> Void)? = nil
                func execute(_ body: @escaping () throws -> Void) throws {
                    executeCallCount += 1
                    executeCallArguments.append(body)
                    if let _handler = executeHandler {
                        try _handler(body)
                    }
                }
                func resetMock() {
                    executeCallCount = 0
                    executeCallArguments = []
                    executeHandler = nil
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
