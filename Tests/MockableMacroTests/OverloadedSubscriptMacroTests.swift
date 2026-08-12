import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import MockableMacros

@Suite("Overloaded Subscript Macro Tests")
struct OverloadedSubscriptMacroTests {
    private let testMacros: [String: Macro.Type] = [
        "Mockable": MockableMacro.self
    ]

    @Test("Subscripts with identical parameters are disambiguated by return type")
    func returnTypeDisambiguation() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Registry {
                subscript(key: String) -> Int { get }
                subscript(key: String) -> Bool { get }
            }
            """,
            expandedSource: """
            protocol Registry {
                subscript(key: String) -> Int { get }
                subscript(key: String) -> Bool { get }
            }

            #if DEBUG
            class RegistryMock: Registry {
                var subscriptStringIntCallCount: Int = 0
                var subscriptStringIntCallArgs: [String] = []
                var subscriptStringIntHandler: (@Sendable (String) -> Int )? = nil
                subscript(key: String) -> Int {
                    subscriptStringIntCallCount += 1
                    subscriptStringIntCallArgs.append(key)
                    guard let _handler = subscriptStringIntHandler else {
                        fatalError("\\(Self.self).subscriptStringIntHandler is not set")
                    }
                    return _handler(key)
                }
                var subscriptStringBoolCallCount: Int = 0
                var subscriptStringBoolCallArgs: [String] = []
                var subscriptStringBoolHandler: (@Sendable (String) -> Bool )? = nil
                subscript(key: String) -> Bool {
                    subscriptStringBoolCallCount += 1
                    subscriptStringBoolCallArgs.append(key)
                    guard let _handler = subscriptStringBoolHandler else {
                        fatalError("\\(Self.self).subscriptStringBoolHandler is not set")
                    }
                    return _handler(key)
                }
                func resetMock() {
                    subscriptStringIntCallCount = 0
                    subscriptStringIntCallArgs = []
                    subscriptStringIntHandler = nil
                    subscriptStringBoolCallCount = 0
                    subscriptStringBoolCallArgs = []
                    subscriptStringBoolHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Subscripts still colliding after the return type get a source-order ordinal")
    func ordinalDisambiguation() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Container {
                subscript(value: Foo<Bar, Baz>) -> Int { get }
                subscript(value: Foo<BarBaz>) -> Int { get }
            }
            """,
            expandedSource: """
            protocol Container {
                subscript(value: Foo<Bar, Baz>) -> Int { get }
                subscript(value: Foo<BarBaz>) -> Int { get }
            }

            #if DEBUG
            class ContainerMock: Container {
                var subscriptFooBarBazIntCallCount: Int = 0
                var subscriptFooBarBazIntCallArgs: [Foo<Bar, Baz>] = []
                var subscriptFooBarBazIntHandler: (@Sendable (Foo<Bar, Baz>) -> Int )? = nil
                subscript(value: Foo<Bar, Baz>) -> Int {
                    subscriptFooBarBazIntCallCount += 1
                    subscriptFooBarBazIntCallArgs.append(value)
                    guard let _handler = subscriptFooBarBazIntHandler else {
                        fatalError("\\(Self.self).subscriptFooBarBazIntHandler is not set")
                    }
                    return _handler(value)
                }
                var subscriptFooBarBazInt2CallCount: Int = 0
                var subscriptFooBarBazInt2CallArgs: [Foo<BarBaz>] = []
                var subscriptFooBarBazInt2Handler: (@Sendable (Foo<BarBaz>) -> Int )? = nil
                subscript(value: Foo<BarBaz>) -> Int {
                    subscriptFooBarBazInt2CallCount += 1
                    subscriptFooBarBazInt2CallArgs.append(value)
                    guard let _handler = subscriptFooBarBazInt2Handler else {
                        fatalError("\\(Self.self).subscriptFooBarBazInt2Handler is not set")
                    }
                    return _handler(value)
                }
                func resetMock() {
                    subscriptFooBarBazIntCallCount = 0
                    subscriptFooBarBazIntCallArgs = []
                    subscriptFooBarBazIntHandler = nil
                    subscriptFooBarBazInt2CallCount = 0
                    subscriptFooBarBazInt2CallArgs = []
                    subscriptFooBarBazInt2Handler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("An overloaded get-set subscript keeps distinct set handlers")
    func getSetOverloadDisambiguation() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Store {
                subscript(key: String) -> Int { get set }
                subscript(key: String) -> Bool { get set }
            }
            """,
            expandedSource: """
            protocol Store {
                subscript(key: String) -> Int { get set }
                subscript(key: String) -> Bool { get set }
            }

            #if DEBUG
            class StoreMock: Store {
                var subscriptStringIntCallCount: Int = 0
                var subscriptStringIntCallArgs: [String] = []
                var subscriptStringIntHandler: (@Sendable (String) -> Int )? = nil
                var subscriptStringIntSetHandler: (@Sendable (String, Int ) -> Void)? = nil
                subscript(key: String) -> Int {
                    get {
                        subscriptStringIntCallCount += 1
                        subscriptStringIntCallArgs.append(key)
                        guard let _handler = subscriptStringIntHandler else {
                            fatalError("\\(Self.self).subscriptStringIntHandler is not set")
                        }
                        return _handler(key)
                    }
                    set {
                        if let _handler = subscriptStringIntSetHandler {
                            _handler(key, newValue)
                        }
                    }
                }
                var subscriptStringBoolCallCount: Int = 0
                var subscriptStringBoolCallArgs: [String] = []
                var subscriptStringBoolHandler: (@Sendable (String) -> Bool )? = nil
                var subscriptStringBoolSetHandler: (@Sendable (String, Bool ) -> Void)? = nil
                subscript(key: String) -> Bool {
                    get {
                        subscriptStringBoolCallCount += 1
                        subscriptStringBoolCallArgs.append(key)
                        guard let _handler = subscriptStringBoolHandler else {
                            fatalError("\\(Self.self).subscriptStringBoolHandler is not set")
                        }
                        return _handler(key)
                    }
                    set {
                        if let _handler = subscriptStringBoolSetHandler {
                            _handler(key, newValue)
                        }
                    }
                }
                func resetMock() {
                    subscriptStringIntCallCount = 0
                    subscriptStringIntCallArgs = []
                    subscriptStringIntHandler = nil
                    subscriptStringIntSetHandler = nil
                    subscriptStringBoolCallCount = 0
                    subscriptStringBoolCallArgs = []
                    subscriptStringBoolHandler = nil
                    subscriptStringBoolSetHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }
}
