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
                var childMethodCallArguments: [()] = []
                var childMethodHandler: (@Sendable () -> Void)? = nil
                func childMethod() {
                    childMethodCallCount += 1
                    childMethodCallArguments.append(())
                    if let _handler = childMethodHandler {
                        _handler()
                    }
                }
                override func resetMock() {
                    super.resetMock()
                    childMethodCallCount = 0
                    childMethodCallArguments = []
                    childMethodHandler = nil
                }
                override class func resetMock() {
                    super.resetMock()
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
                var doSomethingCallArguments: [()] = []
                var doSomethingHandler: (@Sendable () -> Void)? = nil
                func doSomething() {
                    doSomethingCallCount += 1
                    doSomethingCallArguments.append(())
                    if let _handler = doSomethingHandler {
                        _handler()
                    }
                }
                func resetMock() {
                    doSomethingCallCount = 0
                    doSomethingCallArguments = []
                    doSomethingHandler = nil
                }
                class func resetMock() {
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
                var childMethodCallArguments: [()] = []
                var childMethodHandler: (@Sendable () -> Void)? = nil
                func childMethod() {
                    childMethodCallCount += 1
                    childMethodCallArguments.append(())
                    if let _handler = childMethodHandler {
                        _handler()
                    }
                }
                override func resetMock() {
                    super.resetMock()
                    childMethodCallCount = 0
                    childMethodCallArguments = []
                    childMethodHandler = nil
                }
                override class func resetMock() {
                    super.resetMock()
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
                var fetchChildCallArguments: [Int] = []
                var fetchChildHandler: (@Sendable (Int) -> String)? = nil
                func fetchChild(id: Int) -> String {
                    fetchChildCallCount += 1
                    fetchChildCallArguments.append(id)
                    guard let _handler = fetchChildHandler else {
                        fatalError("\\(Self.self).fetchChildHandler is not set")
                    }
                    return _handler(id)
                }
                override func resetMock() {
                    super.resetMock()
                    fetchChildCallCount = 0
                    fetchChildCallArguments = []
                    fetchChildHandler = nil
                }
                override class func resetMock() {
                    super.resetMock()
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Public protocol inheritance keeps mock subclassable across modules")
    func publicParentProtocol() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            public protocol ChildService: BaseService {
                func fetchChild(id: Int) -> String
            }
            """,
            expandedSource: """
            public protocol ChildService: BaseService {
                func fetchChild(id: Int) -> String
            }

            #if DEBUG
            open class ChildServiceMock: BaseServiceMock, ChildService {
                public var fetchChildCallCount: Int = 0
                public var fetchChildCallArguments: [Int] = []
                public var fetchChildHandler: (@Sendable (Int) -> String)? = nil
                public func fetchChild(id: Int) -> String {
                    fetchChildCallCount += 1
                    fetchChildCallArguments.append(id)
                    guard let _handler = fetchChildHandler else {
                        fatalError("\\(Self.self).fetchChildHandler is not set")
                    }
                    return _handler(id)
                }
                open override func resetMock() {
                    super.resetMock()
                    fetchChildCallCount = 0
                    fetchChildCallArguments = []
                    fetchChildHandler = nil
                }
                open override class func resetMock() {
                    super.resetMock()
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Sendable protocol inheriting from parent uses MockableLock with override and super")
    func parentAndSendableMockableLock() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Child: Base, Sendable {
                func childMethod() -> String
            }
            """,
            expandedSource: """
            protocol Child: Base, Sendable {
                func childMethod() -> String
            }

            #if DEBUG
            class ChildMock: BaseMock, Child, @unchecked Sendable {
                private struct Storage {
                    var childMethodCallCount: Int = 0
                    var childMethodCallArguments: [()] = []
                    var childMethodHandler: (@Sendable () -> String)? = nil
                }
                private let _storage = MockableLock<Storage>(Storage())
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
                var childMethodCallArguments: [()] {
                    get {
                        _storage.withLock {
                            $0.childMethodCallArguments
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.childMethodCallArguments = newValue
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
                        storage.childMethodCallArguments.append(())
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
                        storage.childMethodCallArguments = []
                        storage.childMethodHandler = nil
                    }
                }
                override class func resetMock() {
                    super.resetMock()
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Non-Sendable child inheriting from Sendable parent does not use final")
    func sendableParentNonSendableChild() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Child: SendableBase {
                func childMethod() -> Int
            }
            """,
            expandedSource: """
            protocol Child: SendableBase {
                func childMethod() -> Int
            }

            #if DEBUG
            class ChildMock: SendableBaseMock, Child {
                var childMethodCallCount: Int = 0
                var childMethodCallArguments: [()] = []
                var childMethodHandler: (@Sendable () -> Int)? = nil
                func childMethod() -> Int {
                    childMethodCallCount += 1
                    childMethodCallArguments.append(())
                    guard let _handler = childMethodHandler else {
                        fatalError("\\(Self.self).childMethodHandler is not set")
                    }
                    return _handler()
                }
                override func resetMock() {
                    super.resetMock()
                    childMethodCallCount = 0
                    childMethodCallArguments = []
                    childMethodHandler = nil
                }
                override class func resetMock() {
                    super.resetMock()
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }
}
