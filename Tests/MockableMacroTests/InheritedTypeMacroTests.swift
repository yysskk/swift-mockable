import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import MockableMacros

/// How the types in a protocol's inheritance clause are classified: a marker the mock
/// conforms to for free, a parent protocol whose mock it subclasses, or a conformance
/// it cannot satisfy and reports instead.
@Suite("Inherited Type Macro Tests")
struct InheritedTypeMacroTests {
    let testMacros: [String: Macro.Type] = [
        "Mockable": MockableMacro.self
    ]

    // MARK: - Markers

    @Test("A module-qualified Sendable conformance selects the lock-backed storage model")
    func qualifiedSendableConformance() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Service: Swift.Sendable {
                func run()
            }
            """,
            expandedSource: """
            protocol Service: Swift.Sendable {
                func run()
            }

            #if DEBUG
            class ServiceMock: Service, @unchecked Sendable {
                private struct Storage {
                    var runCallCount: Int = 0
                    var runCallArgs: [()] = []
                    var runHandler: (@Sendable () -> Void)? = nil
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
                var runHandler: (@Sendable () -> Void)? {
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
                func run() {
                    let _handler = _storage.withLock { storage -> (@Sendable () -> Void)? in
                        storage.runCallCount += 1
                        storage.runCallArgs.append(())
                        return storage.runHandler
                    }
                    if let _handler {
                        _handler()
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

    @Test("An AnyObject conformance is not treated as a parent protocol")
    func anyObjectConformance() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Service: AnyObject {
                func run()
            }
            """,
            expandedSource: """
            protocol Service: AnyObject {
                func run()
            }

            #if DEBUG
            class ServiceMock: Service {
                var runCallCount: Int = 0
                var runCallArgs: [()] = []
                var runHandler: (@Sendable () -> Void)? = nil
                func run() {
                    runCallCount += 1
                    runCallArgs.append(())
                    if let _handler = runHandler {
                        _handler()
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

    // MARK: - Conformances the mock cannot satisfy

    @Test("A standard-library protocol with requirements is reported")
    func unwitnessableConformance() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Token: Hashable {
                var raw: String { get }
            }
            """,
            expandedSource: """
            protocol Token: Hashable {
                var raw: String { get }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: """
                        'Hashable' declares requirements @Mockable cannot generate witnesses for, \
                        so the generated mock would not conform to it. Drop the conformance from \
                        the protocol, or satisfy it in an extension of the generated mock.
                        """,
                    line: 2,
                    column: 17
                )
            ],
            macros: testMacros
        )
    }

    @Test("A parent protocol written with generic arguments is reported")
    func parameterizedParentConformance() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Service: Container<Int> {
                func run()
            }
            """,
            expandedSource: """
            protocol Service: Container<Int> {
                func run()
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: """
                        'Container<Int>' is a parent protocol written with generic arguments, which the \
                        generated mock cannot subclass. Inherit from an unparameterized protocol \
                        instead.
                        """,
                    line: 2,
                    column: 19
                )
            ],
            macros: testMacros
        )
    }

    // MARK: - Naming

    @Test("An escaped protocol name produces a plain mock type name")
    func escapedProtocolName() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol `Type` {
                func run()
            }
            """,
            expandedSource: """
            protocol `Type` {
                func run()
            }

            #if DEBUG
            class TypeMock: `Type` {
                var runCallCount: Int = 0
                var runCallArgs: [()] = []
                var runHandler: (@Sendable () -> Void)? = nil
                func run() {
                    runCallCount += 1
                    runCallArgs.append(())
                    if let _handler = runHandler {
                        _handler()
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

    // MARK: - Initializer requirements

    @Test("An init requirement is allowed on an actor protocol with a parent")
    func initializerOnActorProtocolWithParent() {
        // An actor mock is final and never subclasses, so there is no parent
        // initializer for the witness to chain through.
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Worker: BaseService, Actor {
                init(name: String)
            }
            """,
            expandedSource: """
            protocol Worker: BaseService, Actor {
                init(name: String)
            }

            #if DEBUG
            actor WorkerMock: Worker {
                private struct Storage {
                    var initCallCount: Int = 0
                    var initCallArgs: [String] = []
                }
                private let _storage = MockableLock<Storage>(Storage())
                nonisolated var initCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.initCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.initCallCount = newValue
                        }
                    }
                }
                nonisolated var initCallArgs: [String] {
                    get {
                        _storage.withLock {
                            $0.initCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.initCallArgs = newValue
                        }
                    }
                }
                init(name: String) {
                    _storage.withLock { storage in
                        storage.initCallCount += 1
                        storage.initCallArgs.append(name)
                    }
                }
                nonisolated func resetMock() {
                    _storage.withLock { storage in
                        storage.initCallCount = 0
                        storage.initCallArgs = []
                    }
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }
}
