import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import MockableMacros

@Suite("Multi-Parameter Handler Tests")
struct MultiParameterHandlerTests {
    private let testMacros: [String: Macro.Type] = [
        "Mockable": MockableMacro.self
    ]

    @Test("Multi-parameter method generates an individual-parameter handler")
    func multiParameterHandler() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Calculator {
                func add(a: Int, b: Int) -> Int
            }
            """,
            expandedSource: """
            protocol Calculator {
                func add(a: Int, b: Int) -> Int
            }

            #if DEBUG
            class CalculatorMock: Calculator {
                var addCallCount: Int = 0
                var addCallArgs: [(a: Int, b: Int)] = []
                var addHandler: (@Sendable (Int, Int) -> Int)? = nil
                func add(a: Int, b: Int) -> Int {
                    addCallCount += 1
                    addCallArgs.append((a: a, b: b))
                    guard let _handler = addHandler else {
                        fatalError("\\(Self.self).addHandler is not set")
                    }
                    return _handler(a, b)
                }
                func resetMock() {
                    addCallCount = 0
                    addCallArgs = []
                    addHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Single-parameter method passes its argument directly")
    func singleParameterHandler() {
        assertMacroExpansionForTesting(
            """
            @Mockable
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

    @Test("Variadic trailing parameter stays an array in the handler")
    func variadicParameter() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Logger {
                func log(_ tag: String, _ messages: String...)
            }
            """,
            expandedSource: """
            protocol Logger {
                func log(_ tag: String, _ messages: String...)
            }

            #if DEBUG
            class LoggerMock: Logger {
                var logCallCount: Int = 0
                var logCallArgs: [(tag: String, messages: [String])] = []
                var logHandler: (@Sendable (String, [String]) -> Void)? = nil
                func log(_ tag: String, _ messages: String...) {
                    logCallCount += 1
                    logCallArgs.append((tag: tag, messages: messages))
                    if let _handler = logHandler {
                        _handler(tag, messages)
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

    @Test("Sendable lock-based mock uses individual-parameter handler")
    func sendableMultiParameterHandler() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Adder: Sendable {
                func add(a: Int, b: Int) -> Int
            }
            """,
            expandedSource: """
            protocol Adder: Sendable {
                func add(a: Int, b: Int) -> Int
            }

            #if DEBUG
            class AdderMock: Adder, @unchecked Sendable {
                private struct Storage {
                    var addCallCount: Int = 0
                    var addCallArgs: [(a: Int, b: Int)] = []
                    var addHandler: (@Sendable (Int, Int) -> Int)? = nil
                }
                private let _storage = MockableLock<Storage>(Storage())
                var addCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.addCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.addCallCount = newValue
                        }
                    }
                }
                var addCallArgs: [(a: Int, b: Int)] {
                    get {
                        _storage.withLock {
                            $0.addCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.addCallArgs = newValue
                        }
                    }
                }
                var addHandler: (@Sendable (Int, Int) -> Int)? {
                    get {
                        _storage.withLock {
                            $0.addHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.addHandler = newValue
                        }
                    }
                }
                func add(a: Int, b: Int) -> Int {
                    let _handler = _storage.withLock { storage -> (@Sendable (Int, Int) -> Int)? in
                        storage.addCallCount += 1
                        storage.addCallArgs.append((a: a, b: b))
                        return storage.addHandler
                    }
                    guard let _handler else {
                        fatalError("\\(Self.self).addHandler is not set")
                    }
                    return _handler(a, b)
                }
                func resetMock() {
                    _storage.withLock { storage in
                        storage.addCallCount = 0
                        storage.addCallArgs = []
                        storage.addHandler = nil
                    }
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Subscript getter and setter use individual parameters")
    func subscriptMultiParameterHandler() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Grid {
                subscript(row: Int, col: Int) -> Int { get set }
            }
            """,
            expandedSource: """
            protocol Grid {
                subscript(row: Int, col: Int) -> Int { get set }
            }

            #if DEBUG
            class GridMock: Grid {
                var subscriptIntIntCallCount: Int = 0
                var subscriptIntIntCallArgs: [(row: Int, col: Int)] = []
                var subscriptIntIntHandler: (@Sendable (Int, Int) -> Int )? = nil
                var subscriptIntIntSetHandler: (@Sendable (Int, Int, Int ) -> Void)? = nil
                subscript(row: Int, col: Int) -> Int {
                    get {
                        subscriptIntIntCallCount += 1
                        subscriptIntIntCallArgs.append((row: row, col: col))
                        guard let _handler = subscriptIntIntHandler else {
                            fatalError("\\(Self.self).subscriptIntIntHandler is not set")
                        }
                        return _handler(row, col)
                    }
                    set {
                        if let _handler = subscriptIntIntSetHandler {
                            _handler(row, col, newValue)
                        }
                    }
                }
                func resetMock() {
                    subscriptIntIntCallCount = 0
                    subscriptIntIntCallArgs = []
                    subscriptIntIntHandler = nil
                    subscriptIntIntSetHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }
}
