import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import MockableMacros

@Suite("Autoclosure Macro Tests")
struct AutoclosureMacroTests {
    private let testMacros: [String: Macro.Type] = [
        "Mockable": MockableMacro.self
    ]

    @Test("@autoclosure parameter is evaluated once and recorded by value")
    func autoclosureParameterIsEvaluated() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Logger {
                func log(_ message: @autoclosure () -> String)
            }
            """,
            expandedSource: """
            protocol Logger {
                func log(_ message: @autoclosure () -> String)
            }

            #if DEBUG
            class LoggerMock: Logger {
                var logCallCount: Int = 0
                var logCallArgs: [String] = []
                var logHandler: (@Sendable (String) -> Void)? = nil
                func log(_ message: @autoclosure () -> String) {
                    let message = message()
                    logCallCount += 1
                    logCallArgs.append(message)
                    if let _handler = logHandler {
                        _handler(message)
                    }
                }
                func resetMock() {
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

    @Test("throwing @autoclosure parameter in a throws requirement uses try")
    func throwingAutoclosureParameterUsesTry() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Calculator {
                func compute(_ value: @autoclosure () throws -> Int) throws -> Int
            }
            """,
            expandedSource: """
            protocol Calculator {
                func compute(_ value: @autoclosure () throws -> Int) throws -> Int
            }

            #if DEBUG
            class CalculatorMock: Calculator {
                var computeCallCount: Int = 0
                var computeCallArgs: [Int] = []
                var computeHandler: (@Sendable (Int) throws -> Int)? = nil
                func compute(_ value: @autoclosure () throws -> Int) throws -> Int {
                    let value = try value()
                    computeCallCount += 1
                    computeCallArgs.append(value)
                    guard let _handler = computeHandler else {
                        fatalError("\\(Self.self).computeHandler is not set")
                    }
                    return try _handler(value)
                }
                func resetMock() {
                    computeCallCount = 0
                    computeCallArgs = []
                    computeHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("@autoclosure @escaping parameter is evaluated the same way")
    func escapingAutoclosureParameterIsEvaluated() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Scheduler {
                func schedule(_ work: @autoclosure @escaping () -> Int)
            }
            """,
            expandedSource: """
            protocol Scheduler {
                func schedule(_ work: @autoclosure @escaping () -> Int)
            }

            #if DEBUG
            class SchedulerMock: Scheduler {
                var scheduleCallCount: Int = 0
                var scheduleCallArgs: [Int] = []
                var scheduleHandler: (@Sendable (Int) -> Void)? = nil
                func schedule(_ work: @autoclosure @escaping () -> Int) {
                    let work = work()
                    scheduleCallCount += 1
                    scheduleCallArgs.append(work)
                    if let _handler = scheduleHandler {
                        _handler(work)
                    }
                }
                func resetMock() {
                    scheduleCallCount = 0
                    scheduleCallArgs = []
                    scheduleHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("mixed parameters evaluate only the @autoclosure argument")
    func mixedParametersEvaluateOnlyAutoclosure() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Recorder {
                func record(name: String, value: @autoclosure () -> Int)
            }
            """,
            expandedSource: """
            protocol Recorder {
                func record(name: String, value: @autoclosure () -> Int)
            }

            #if DEBUG
            class RecorderMock: Recorder {
                var recordCallCount: Int = 0
                var recordCallArgs: [(name: String, value: Int)] = []
                var recordHandler: (@Sendable (String, Int) -> Void)? = nil
                func record(name: String, value: @autoclosure () -> Int) {
                    let value = value()
                    recordCallCount += 1
                    recordCallArgs.append((name: name, value: value))
                    if let _handler = recordHandler {
                        _handler(name, value)
                    }
                }
                func resetMock() {
                    recordCallCount = 0
                    recordCallArgs = []
                    recordHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Sendable protocol evaluates @autoclosure arguments before locking")
    func sendableProtocolEvaluatesAutoclosureBeforeLocking() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol MetricsRecorder: Sendable {
                func record(_ value: @autoclosure () -> Int)
            }
            """,
            expandedSource: """
            protocol MetricsRecorder: Sendable {
                func record(_ value: @autoclosure () -> Int)
            }

            #if DEBUG
            class MetricsRecorderMock: MetricsRecorder, @unchecked Sendable {
                private struct Storage {
                    var recordCallCount: Int = 0
                    var recordCallArgs: [Int] = []
                    var recordHandler: (@Sendable (Int) -> Void)? = nil
                }
                private let _storage = MockableLock<Storage>(Storage())
                var recordCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.recordCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.recordCallCount = newValue
                        }
                    }
                }
                var recordCallArgs: [Int] {
                    get {
                        _storage.withLock {
                            $0.recordCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.recordCallArgs = newValue
                        }
                    }
                }
                var recordHandler: (@Sendable (Int) -> Void)? {
                    get {
                        _storage.withLock {
                            $0.recordHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.recordHandler = newValue
                        }
                    }
                }
                func record(_ value: @autoclosure () -> Int) {
                    let value = value()
                    let _handler = _storage.withLock { storage -> (@Sendable (Int) -> Void)? in
                        storage.recordCallCount += 1
                        storage.recordCallArgs.append(value)
                        return storage.recordHandler
                    }
                    if let _handler {
                        _handler(value)
                    }
                }
                func resetMock() {
                    _storage.withLock { storage in
                        storage.recordCallCount = 0
                        storage.recordCallArgs = []
                        storage.recordHandler = nil
                    }
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("throwing @autoclosure in a non-throwing requirement produces a diagnostic")
    func throwingAutoclosureInNonThrowingRequirementProducesDiagnostic() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Cache {
                func store(_ value: @autoclosure () throws -> Int)
            }
            """,
            expandedSource: """
            protocol Cache {
                func store(_ value: @autoclosure () throws -> Int)
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Cannot mock @autoclosure parameter 'value': the mock evaluates autoclosure arguments when called, so the requirement must be declared 'throws'",
                    line: 3,
                    column: 16
                )
            ],
            macros: testMacros
        )
    }

    @Test("async @autoclosure in a synchronous requirement produces a diagnostic")
    func asyncAutoclosureInSynchronousRequirementProducesDiagnostic() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Loader {
                func load(_ value: @autoclosure () async -> Int)
            }
            """,
            expandedSource: """
            protocol Loader {
                func load(_ value: @autoclosure () async -> Int)
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Cannot mock @autoclosure parameter 'value': the mock evaluates autoclosure arguments when called, so the requirement must be declared 'async'",
                    line: 3,
                    column: 15
                )
            ],
            macros: testMacros
        )
    }

    @Test("effectful @autoclosure in a subscript requirement produces a diagnostic")
    func effectfulAutoclosureInSubscriptProducesDiagnostic() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Store {
                subscript(key: @autoclosure () throws -> String) -> Int { get }
            }
            """,
            expandedSource: """
            protocol Store {
                subscript(key: @autoclosure () throws -> String) -> Int { get }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Cannot mock @autoclosure parameter 'key': effectful autoclosures are not supported in subscript requirements",
                    line: 3,
                    column: 15
                )
            ],
            macros: testMacros
        )
    }
}
