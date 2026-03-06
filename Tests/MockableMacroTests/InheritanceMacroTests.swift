import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import MockableMacros

@Suite("Inheritance Macro Tests")
struct InheritanceMacroTests {
    private let testMacros: [String: Macro.Type] = [
        "Mockable": MockableMacro.self
    ]

    @Test("Protocol inheriting from another protocol generates mock with parent mock superclass")
    func singleParentProtocol() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Child: Base {
                func childMethod()
            }
            """,
            expandedSource: """
            protocol Child: Base {
                func childMethod()
            }

            #if DEBUG
            class ChildMock: BaseMock, Child {
                var childMethodCallCount: Int = 0
                var childMethodCallArgs: [()] = []
                var childMethodHandler: (@Sendable () -> Void)? = nil
                func childMethod() {
                    childMethodCallCount += 1
                    childMethodCallArgs.append(())
                    if let _handler = childMethodHandler {
                        _handler()
                    }
                }
                override func resetMock() {
                    super.resetMock()
                    childMethodCallCount = 0
                    childMethodCallArgs = []
                    childMethodHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol inheriting from AnyObject does not use parent mock")
    func anyObjectInheritance() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol MyProtocol: AnyObject {
                func doSomething()
            }
            """,
            expandedSource: """
            protocol MyProtocol: AnyObject {
                func doSomething()
            }

            #if DEBUG
            class MyProtocolMock: MyProtocol {
                var doSomethingCallCount: Int = 0
                var doSomethingCallArgs: [()] = []
                var doSomethingHandler: (@Sendable () -> Void)? = nil
                func doSomething() {
                    doSomethingCallCount += 1
                    doSomethingCallArgs.append(())
                    if let _handler = doSomethingHandler {
                        _handler()
                    }
                }
                func resetMock() {
                    doSomethingCallCount = 0
                    doSomethingCallArgs = []
                    doSomethingHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with multiple parent protocols uses first as superclass")
    func multipleParentProtocols() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Child: ParentA, ParentB {
                func childMethod()
            }
            """,
            expandedSource: """
            protocol Child: ParentA, ParentB {
                func childMethod()
            }

            #if DEBUG
            class ChildMock: ParentAMock, Child {
                var childMethodCallCount: Int = 0
                var childMethodCallArgs: [()] = []
                var childMethodHandler: (@Sendable () -> Void)? = nil
                func childMethod() {
                    childMethodCallCount += 1
                    childMethodCallArgs.append(())
                    if let _handler = childMethodHandler {
                        _handler()
                    }
                }
                override func resetMock() {
                    super.resetMock()
                    childMethodCallCount = 0
                    childMethodCallArgs = []
                    childMethodHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with parent, method with parameters, and return value")
    func parentProtocolWithParameters() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol ChildService: BaseService {
                func fetchChild(id: Int) -> String
            }
            """,
            expandedSource: """
            protocol ChildService: BaseService {
                func fetchChild(id: Int) -> String
            }

            #if DEBUG
            class ChildServiceMock: BaseServiceMock, ChildService {
                var fetchChildCallCount: Int = 0
                var fetchChildCallArgs: [Int] = []
                var fetchChildHandler: (@Sendable (Int) -> String)? = nil
                func fetchChild(id: Int) -> String {
                    fetchChildCallCount += 1
                    fetchChildCallArgs.append(id)
                    guard let _handler = fetchChildHandler else {
                        fatalError("\\(Self.self).fetchChildHandler is not set")
                    }
                    return _handler(id)
                }
                override func resetMock() {
                    super.resetMock()
                    fetchChildCallCount = 0
                    fetchChildCallArgs = []
                    fetchChildHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Sendable protocol inheriting from parent uses legacyLock with override and super")
    func parentAndSendableLegacyLock() {
        assertMacroExpansionForTesting(
            """
            @Mockable(legacyLock: true)
            protocol Child: Base, Sendable {
                func childMethod() -> String
            }
            """,
            expandedSource: """
            protocol Child: Base, Sendable {
                func childMethod() -> String
            }

            #if DEBUG
            final class ChildMock: BaseMock, Child, Sendable {
                private struct Storage {
                    var childMethodCallCount: Int = 0
                    var childMethodCallArgs: [()] = []
                    var childMethodHandler: (@Sendable () -> String)? = nil
                }
                private let _storage = LegacyLock<Storage>(Storage())
                var childMethodCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.childMethodCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.childMethodCallCount = newValue
                        }
                    }
                }
                var childMethodCallArgs: [()] {
                    get {
                        _storage.withLock {
                            $0.childMethodCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.childMethodCallArgs = newValue
                        }
                    }
                }
                var childMethodHandler: (@Sendable () -> String)? {
                    get {
                        _storage.withLock {
                            $0.childMethodHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.childMethodHandler = newValue
                        }
                    }
                }
                func childMethod() -> String {
                    let _handler = _storage.withLock { storage -> (@Sendable () -> String)? in
                        storage.childMethodCallCount += 1
                        storage.childMethodCallArgs.append(())
                        return storage.childMethodHandler
                    }
                    guard let _handler else {
                        fatalError("\\(Self.self).childMethodHandler is not set")
                    }
                    return _handler()
                }
                override func resetMock() {
                    super.resetMock()
                    _storage.withLock { storage in
                        storage.childMethodCallCount = 0
                        storage.childMethodCallArgs = []
                        storage.childMethodHandler = nil
                    }
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }
}
