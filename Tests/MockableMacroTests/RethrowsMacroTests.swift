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
                var runCallArguments: [()] = []
                var runHandler: (@Sendable (() throws -> Void) -> Void)? = nil
                func run(_ body: () throws -> Void) rethrows {
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
                var transformCallArguments: [()] = []
                var transformHandler: (@Sendable ((Int) throws -> Int) -> Int)? = nil
                func transform(_ body: (Int) throws -> Int) rethrows -> Int {
                    transformCallCount += 1
                    transformCallArguments.append(())
                    guard let _handler = transformHandler else {
                        fatalError("\\(Self.self).transformHandler is not set")
                    }
                    return _handler(body)
                }
                func resetMock() {
                    transformCallCount = 0
                    transformCallArguments = []
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
                    var runCallArguments: [()] = []
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
                var runCallArguments: [()] {
                    get {
                        _storage.withLock {
                            $0.runCallArguments
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.runCallArguments = newValue
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
                        storage.runCallArguments.append(())
                        return storage.runHandler
                    }
                    if let _handler {
                        _handler(body)
                    }
                }
                func resetMock() {
                    _storage.withLock { storage in
                        storage.runCallCount = 0
                        storage.runCallArguments = []
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
                var executeCallCount: Int = 0
                var executeCallArguments: [() throws -> Void] = []
                var executeHandler: (@Sendable (() throws -> Void) throws -> Void)? = nil
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
