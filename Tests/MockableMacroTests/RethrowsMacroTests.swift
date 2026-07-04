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
                var runCallCount: Int = 0
                var runCallArgs: [()] = []
                var runHandler: (@Sendable (() throws -> Void) -> Void)? = nil
                func run(_ body: () throws -> Void) rethrows {
                    runCallCount += 1
                    runCallArgs.append(())
                    if let _handler = runHandler {
                        _handler(body)
                    }
                }
                func resetMock() {
                    runCallCount = 0
                    runCallArgs = []
                    runHandler = nil
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
                var transformCallCount: Int = 0
                var transformCallArgs: [()] = []
                var transformHandler: (@Sendable ((Int) throws -> Int) -> Int)? = nil
                func transform(_ body: (Int) throws -> Int) rethrows -> Int {
                    transformCallCount += 1
                    transformCallArgs.append(())
                    guard let _handler = transformHandler else {
                        fatalError("\\(Self.self).transformHandler is not set")
                    }
                    return _handler(body)
                }
                func resetMock() {
                    transformCallCount = 0
                    transformCallArgs = []
                    transformHandler = nil
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
                    var runCallArgs: [()] = []
                    var runHandler: (@Sendable (@Sendable () throws -> Void) -> Void)? = nil
                }
                private let _storage = MockableLock<Storage>(Storage())
                var runCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.runCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.runCallCount = newValue
                        }
                    }
                }
                var runCallArgs: [()] {
                    get {
                        _storage.withLock {
                            $0.runCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.runCallArgs = newValue
                        }
                    }
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
                        storage.runCallArgs.append(())
                        return storage.runHandler
                    }
                    if let _handler {
                        _handler(body)
                    }
                }
                func resetMock() {
                    _storage.withLock { storage in
                        storage.runCallCount = 0
                        storage.runCallArgs = []
                        storage.runHandler = nil
                    }
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
