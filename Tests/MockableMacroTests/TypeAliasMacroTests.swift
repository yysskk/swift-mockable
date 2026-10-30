import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import MockableMacros

@Suite("TypeAlias Macro Tests")
struct TypeAliasMacroTests {
    private let testMacros: [String: Macro.Type] = [
        "Mockable": MockableMacro.self
    ]

    @Test("Protocol with typealias")
    func simpleTypealias() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Presenter {
                typealias UpdateType = String
                func update(type: UpdateType)
            }
            """,
            expandedSource: """
            protocol Presenter {
                typealias UpdateType = String
                func update(type: UpdateType)
            }

            #if DEBUG
            class PresenterMock: Presenter {
                typealias UpdateType = String
                private(set) var updateCallCount: Int = 0
                private(set) var updateCallArguments: [UpdateType] = []
                var updateHandler: ((UpdateType) -> Void)? = nil
                func update(type: UpdateType) {
                    updateCallCount += 1
                    updateCallArguments.append(type)
                    if let _handler = updateHandler {
                        _handler(type)
                    }
                }
                func resetMock() {
                    updateCallCount = 0
                    updateCallArguments = []
                    updateHandler = nil
                }
                class func resetMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with multiple typealiases")
    func multipleTypealiases() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Delegate {
                typealias Callback = (String) -> Void
                typealias ID = Int
                func register(id: ID, callback: @escaping Callback)
            }
            """,
            expandedSource: """
            protocol Delegate {
                typealias Callback = (String) -> Void
                typealias ID = Int
                func register(id: ID, callback: @escaping Callback)
            }

            #if DEBUG
            class DelegateMock: Delegate {
                typealias Callback = (String) -> Void
                typealias ID = Int
                private(set) var registerCallCount: Int = 0
                private(set) var registerCallArguments: [(id: ID, callback: Callback)] = []
                var registerHandler: ((ID, Callback) -> Void)? = nil
                func register(id: ID, callback: @escaping Callback) {
                    registerCallCount += 1
                    registerCallArguments.append((id: id, callback: callback))
                    if let _handler = registerHandler {
                        _handler(id, callback)
                    }
                }
                func resetMock() {
                    registerCallCount = 0
                    registerCallArguments = []
                    registerHandler = nil
                }
                class func resetMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with typealias only")
    func typealiasOnly() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol TypeContainer {
                typealias Value = [String: Any]
            }
            """,
            expandedSource: """
            protocol TypeContainer {
                typealias Value = [String: Any]
            }

            #if DEBUG
            class TypeContainerMock: TypeContainer {
                typealias Value = [String: Any]
                func resetMock() {
                }
                class func resetMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Public protocol with typealias")
    func publicProtocolWithTypealias() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            public protocol CartDelegate {
                typealias TableViewUpdateType = String
                func didUpdate(type: TableViewUpdateType)
            }
            """,
            expandedSource: """
            public protocol CartDelegate {
                typealias TableViewUpdateType = String
                func didUpdate(type: TableViewUpdateType)
            }

            #if DEBUG
            open class CartDelegateMock: CartDelegate {
                public typealias TableViewUpdateType = String
                public init() {
                }
                public private(set) var didUpdateCallCount: Int = 0
                public private(set) var didUpdateCallArguments: [TableViewUpdateType] = []
                public var didUpdateHandler: ((TableViewUpdateType) -> Void)? = nil
                public func didUpdate(type: TableViewUpdateType) {
                    didUpdateCallCount += 1
                    didUpdateCallArguments.append(type)
                    if let _handler = didUpdateHandler {
                        _handler(type)
                    }
                }
                open func resetMock() {
                    didUpdateCallCount = 0
                    didUpdateCallArguments = []
                    didUpdateHandler = nil
                }
                open class func resetMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }
}
