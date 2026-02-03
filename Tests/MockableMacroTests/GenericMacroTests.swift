import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import MockableMacros

@Suite("Generic Macro Tests")
struct GenericMacroTests {
    private let testMacros: [String: Macro.Type] = [
        "Mockable": MockableMacro.self
    ]

    @Test("Protocol with generic method returning generic type")
    func genericMethodWithReturn() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Cache {
                func get<T>(_ key: String) -> T
            }
            """,
            expandedSource: """
            protocol Cache {
                func get<T>(_ key: String) -> T
            }

            #if DEBUG
            public class CacheMock: Cache {
                public var getCallCount: Int = 0
                public var getCallArgs: [String] = []
                public var getHandler: (@Sendable (String) -> Any)? = nil
                public func get<T>(_ key: String) -> T {
                    getCallCount += 1
                    getCallArgs.append(key)
                    guard let _handler = getHandler else {
                        fatalError("\\(Self.self).getHandler is not set")
                    }
                    return _handler(key) as! T
                }
                public func resetMock() {
                    getCallCount = 0
                    getCallArgs = []
                    getHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with generic method with generic parameter type")
    func genericMethodWithGenericParameter() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Storage {
                func save<T>(_ value: T, forKey key: String)
            }
            """,
            expandedSource: """
            protocol Storage {
                func save<T>(_ value: T, forKey key: String)
            }

            #if DEBUG
            public class StorageMock: Storage {
                public var saveCallCount: Int = 0
                public var saveCallArgs: [(value: Any, key: String)] = []
                public var saveHandler: (@Sendable ((value: Any, key: String)) -> Void)? = nil
                public func save<T>(_ value: T, forKey key: String) {
                    saveCallCount += 1
                    saveCallArgs.append((value: value, key: key))
                    if let _handler = saveHandler {
                        _handler((value: value, key: key))
                    }
                }
                public func resetMock() {
                    saveCallCount = 0
                    saveCallArgs = []
                    saveHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with generic method using wrapper type like UserDefaultsKey<T>")
    func genericMethodWithWrapperType() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol UserDefaultsClient {
                func get<T>(_ key: UserDefaultsKey<T>) -> T
                func set<T>(_ value: T, forKey key: UserDefaultsKey<T>)
            }
            """,
            expandedSource: """
            protocol UserDefaultsClient {
                func get<T>(_ key: UserDefaultsKey<T>) -> T
                func set<T>(_ value: T, forKey key: UserDefaultsKey<T>)
            }

            #if DEBUG
            public class UserDefaultsClientMock: UserDefaultsClient {
                public var getCallCount: Int = 0
                public var getCallArgs: [Any] = []
                public var getHandler: (@Sendable (Any) -> Any)? = nil
                public func get<T>(_ key: UserDefaultsKey<T>) -> T {
                    getCallCount += 1
                    getCallArgs.append(key)
                    guard let _handler = getHandler else {
                        fatalError("\\(Self.self).getHandler is not set")
                    }
                    return _handler(key) as! T
                }
                public var setCallCount: Int = 0
                public var setCallArgs: [(value: Any, key: Any)] = []
                public var setHandler: (@Sendable ((value: Any, key: Any)) -> Void)? = nil
                public func set<T>(_ value: T, forKey key: UserDefaultsKey<T>) {
                    setCallCount += 1
                    setCallArgs.append((value: value, key: key))
                    if let _handler = setHandler {
                        _handler((value: value, key: key))
                    }
                }
                public func resetMock() {
                    getCallCount = 0
                    getCallArgs = []
                    getHandler = nil
                    setCallCount = 0
                    setCallArgs = []
                    setHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with concrete generic type parameters (non-generic method)")
    func concreteGenericTypeParameters() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol UserDefaultsClient {
                func integer(forKey key: UserDefaultsKey<Int>) -> Int
                func setInteger(_ value: Int, forKey key: UserDefaultsKey<Int>)
            }
            """,
            expandedSource: """
            protocol UserDefaultsClient {
                func integer(forKey key: UserDefaultsKey<Int>) -> Int
                func setInteger(_ value: Int, forKey key: UserDefaultsKey<Int>)
            }

            #if DEBUG
            public class UserDefaultsClientMock: UserDefaultsClient {
                public var integerCallCount: Int = 0
                public var integerCallArgs: [UserDefaultsKey<Int>] = []
                public var integerHandler: (@Sendable (UserDefaultsKey<Int>) -> Int)? = nil
                public func integer(forKey key: UserDefaultsKey<Int>) -> Int {
                    integerCallCount += 1
                    integerCallArgs.append(key)
                    guard let _handler = integerHandler else {
                        fatalError("\\(Self.self).integerHandler is not set")
                    }
                    return _handler(key)
                }
                public var setIntegerCallCount: Int = 0
                public var setIntegerCallArgs: [(value: Int, key: UserDefaultsKey<Int>)] = []
                public var setIntegerHandler: (@Sendable ((value: Int, key: UserDefaultsKey<Int>)) -> Void)? = nil
                public func setInteger(_ value: Int, forKey key: UserDefaultsKey<Int>) {
                    setIntegerCallCount += 1
                    setIntegerCallArgs.append((value: value, key: key))
                    if let _handler = setIntegerHandler {
                        _handler((value: value, key: key))
                    }
                }
                public func resetMock() {
                    integerCallCount = 0
                    integerCallArgs = []
                    integerHandler = nil
                    setIntegerCallCount = 0
                    setIntegerCallArgs = []
                    setIntegerHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }
}
