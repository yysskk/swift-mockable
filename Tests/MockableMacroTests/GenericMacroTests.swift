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
            class CacheMock: Cache {
                var getCallCount: Int = 0
                var getCallArgs: [String] = []
                var getHandler: (@Sendable (String) -> Any)? = nil
                func get<T>(_ key: String) -> T {
                    getCallCount += 1
                    getCallArgs.append(key)
                    guard let _handler = getHandler else {
                        fatalError("\\(Self.self).getHandler is not set")
                    }
                    return _handler(key) as! T
                }
                func resetMock() {
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
            class StorageMock: Storage {
                var saveCallCount: Int = 0
                var saveCallArgs: [(value: Any, key: String)] = []
                var saveHandler: (@Sendable (Any, String) -> Void)? = nil
                func save<T>(_ value: T, forKey key: String) {
                    saveCallCount += 1
                    saveCallArgs.append((value: value, key: key))
                    if let _handler = saveHandler {
                        _handler(value, key)
                    }
                }
                func resetMock() {
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
            class UserDefaultsClientMock: UserDefaultsClient {
                var getCallCount: Int = 0
                var getCallArgs: [Any] = []
                var getHandler: (@Sendable (Any) -> Any)? = nil
                func get<T>(_ key: UserDefaultsKey<T>) -> T {
                    getCallCount += 1
                    getCallArgs.append(key)
                    guard let _handler = getHandler else {
                        fatalError("\\(Self.self).getHandler is not set")
                    }
                    return _handler(key) as! T
                }
                var setCallCount: Int = 0
                var setCallArgs: [(value: Any, key: Any)] = []
                var setHandler: (@Sendable (Any, Any) -> Void)? = nil
                func set<T>(_ value: T, forKey key: UserDefaultsKey<T>) {
                    setCallCount += 1
                    setCallArgs.append((value: value, key: key))
                    if let _handler = setHandler {
                        _handler(value, key)
                    }
                }
                func resetMock() {
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
            class UserDefaultsClientMock: UserDefaultsClient {
                var integerCallCount: Int = 0
                var integerCallArgs: [UserDefaultsKey<Int>] = []
                var integerHandler: (@Sendable (UserDefaultsKey<Int>) -> Int)? = nil
                func integer(forKey key: UserDefaultsKey<Int>) -> Int {
                    integerCallCount += 1
                    integerCallArgs.append(key)
                    guard let _handler = integerHandler else {
                        fatalError("\\(Self.self).integerHandler is not set")
                    }
                    return _handler(key)
                }
                var setIntegerCallCount: Int = 0
                var setIntegerCallArgs: [(value: Int, key: UserDefaultsKey<Int>)] = []
                var setIntegerHandler: (@Sendable (Int, UserDefaultsKey<Int>) -> Void)? = nil
                func setInteger(_ value: Int, forKey key: UserDefaultsKey<Int>) {
                    setIntegerCallCount += 1
                    setIntegerCallArgs.append((value: value, key: key))
                    if let _handler = setIntegerHandler {
                        _handler(value, key)
                    }
                }
                func resetMock() {
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

    @Test("Generic method with optional return returns nil when handler is unset")
    func genericOptionalReturnDefaultsToNil() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Cache {
                func get<T>(_ key: String) -> T?
            }
            """,
            expandedSource: """
            protocol Cache {
                func get<T>(_ key: String) -> T?
            }

            #if DEBUG
            class CacheMock: Cache {
                var getCallCount: Int = 0
                var getCallArgs: [String] = []
                var getHandler: (@Sendable (String) -> Any?)? = nil
                func get<T>(_ key: String) -> T? {
                    getCallCount += 1
                    getCallArgs.append(key)
                    guard let _handler = getHandler else {
                        return nil
                    }
                    return _handler(key) as! T?
                }
                func resetMock() {
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

    @Test("Generic method with a nested generic argument erases the wrapper to Any")
    func genericNestedGenericArgumentErasesWrapper() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Cache {
                func rewrap<T>(_ box: Box<[T]>) -> Box<[T]>
            }
            """,
            expandedSource: """
            protocol Cache {
                func rewrap<T>(_ box: Box<[T]>) -> Box<[T]>
            }

            #if DEBUG
            class CacheMock: Cache {
                var rewrapCallCount: Int = 0
                var rewrapCallArgs: [Any] = []
                var rewrapHandler: (@Sendable (Any) -> Any)? = nil
                func rewrap<T>(_ box: Box<[T]>) -> Box<[T]> {
                    rewrapCallCount += 1
                    rewrapCallArgs.append(box)
                    guard let _handler = rewrapHandler else {
                        fatalError("\\(Self.self).rewrapHandler is not set")
                    }
                    return _handler(box) as! Box<[T]>
                }
                func resetMock() {
                    rewrapCallCount = 0
                    rewrapCallArgs = []
                    rewrapHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Generic method with module-qualified types erases only the generic ones")
    func genericQualifiedTypeErasesToAny() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Cache {
                func store<T>(_ box: MyModule.Box<T>, in container: MyModule.Container)
            }
            """,
            expandedSource: """
            protocol Cache {
                func store<T>(_ box: MyModule.Box<T>, in container: MyModule.Container)
            }

            #if DEBUG
            class CacheMock: Cache {
                var storeCallCount: Int = 0
                var storeCallArgs: [(box: Any, container: MyModule.Container)] = []
                var storeHandler: (@Sendable (Any, MyModule.Container) -> Void)? = nil
                func store<T>(_ box: MyModule.Box<T>, in container: MyModule.Container) {
                    storeCallCount += 1
                    storeCallArgs.append((box: box, container: container))
                    if let _handler = storeHandler {
                        _handler(box, container)
                    }
                }
                func resetMock() {
                    storeCallCount = 0
                    storeCallArgs = []
                    storeHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Generic method with a type nested in a generic parameter erases to Any")
    func genericDependentMemberTypeErasesToAny() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Cache {
                func firstElement<T: Collection>(_ collection: T) -> T.Element
            }
            """,
            expandedSource: """
            protocol Cache {
                func firstElement<T: Collection>(_ collection: T) -> T.Element
            }

            #if DEBUG
            class CacheMock: Cache {
                var firstElementCallCount: Int = 0
                var firstElementCallArgs: [Any] = []
                var firstElementHandler: (@Sendable (Any) -> Any)? = nil
                func firstElement<T: Collection>(_ collection: T) -> T.Element {
                    firstElementCallCount += 1
                    firstElementCallArgs.append(collection)
                    guard let _handler = firstElementHandler else {
                        fatalError("\\(Self.self).firstElementHandler is not set")
                    }
                    return _handler(collection) as! T.Element
                }
                func resetMock() {
                    firstElementCallCount = 0
                    firstElementCallArgs = []
                    firstElementHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Generic method with dictionary value erases the value type to Any")
    func genericDictionaryValueErasesToAny() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Cache {
                func transform<T>(_ map: [String: T]) -> [String: T]
            }
            """,
            expandedSource: """
            protocol Cache {
                func transform<T>(_ map: [String: T]) -> [String: T]
            }

            #if DEBUG
            class CacheMock: Cache {
                var transformCallCount: Int = 0
                var transformCallArgs: [[String: Any]] = []
                var transformHandler: (@Sendable ([String: Any]) -> [String: Any])? = nil
                func transform<T>(_ map: [String: T]) -> [String: T] {
                    transformCallCount += 1
                    transformCallArgs.append(map)
                    guard let _handler = transformHandler else {
                        return [:]
                    }
                    return _handler(map) as! [String: T]
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

    @Test("Generic method with dictionary key erases the whole dictionary to Any")
    func genericDictionaryKeyErasesWholeDictionary() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Cache {
                func index<T: Hashable>(_ map: [T: String]) -> [T: String]
            }
            """,
            expandedSource: """
            protocol Cache {
                func index<T: Hashable>(_ map: [T: String]) -> [T: String]
            }

            #if DEBUG
            class CacheMock: Cache {
                var indexCallCount: Int = 0
                var indexCallArgs: [Any] = []
                var indexHandler: (@Sendable (Any) -> Any)? = nil
                func index<T: Hashable>(_ map: [T: String]) -> [T: String] {
                    indexCallCount += 1
                    indexCallArgs.append(map)
                    guard let _handler = indexHandler else {
                        return [:]
                    }
                    return _handler(map) as! [T: String]
                }
                func resetMock() {
                    indexCallCount = 0
                    indexCallArgs = []
                    indexHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Generic method with dictionary nested in optionals and arrays erases the generic type")
    func genericDictionaryNestedInOptionalAndArray() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Cache {
                func lookup<T>(_ map: [String: [T]]?) -> [String: T]?
            }
            """,
            expandedSource: """
            protocol Cache {
                func lookup<T>(_ map: [String: [T]]?) -> [String: T]?
            }

            #if DEBUG
            class CacheMock: Cache {
                var lookupCallCount: Int = 0
                var lookupCallArgs: [[String: [Any]]?] = []
                var lookupHandler: (@Sendable ([String: [Any]]?) -> [String: Any]?)? = nil
                func lookup<T>(_ map: [String: [T]]?) -> [String: T]? {
                    lookupCallCount += 1
                    lookupCallArgs.append(map)
                    guard let _handler = lookupHandler else {
                        return nil
                    }
                    return _handler(map) as! [String: T]?
                }
                func resetMock() {
                    lookupCallCount = 0
                    lookupCallArgs = []
                    lookupHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Dictionary without generic parameters is kept verbatim in a generic method")
    func nonGenericDictionaryIsKeptVerbatim() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Cache {
                func store<T>(_ value: T, metadata: [String: Int])
            }
            """,
            expandedSource: """
            protocol Cache {
                func store<T>(_ value: T, metadata: [String: Int])
            }

            #if DEBUG
            class CacheMock: Cache {
                var storeCallCount: Int = 0
                var storeCallArgs: [(value: Any, metadata: [String: Int])] = []
                var storeHandler: (@Sendable (Any, [String: Int]) -> Void)? = nil
                func store<T>(_ value: T, metadata: [String: Int]) {
                    storeCallCount += 1
                    storeCallArgs.append((value: value, metadata: metadata))
                    if let _handler = storeHandler {
                        _handler(value, metadata)
                    }
                }
                func resetMock() {
                    storeCallCount = 0
                    storeCallArgs = []
                    storeHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Generic method with array return returns empty array when handler is unset")
    func genericArrayReturnDefaultsToEmptyArray() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Cache {
                func get<T>(_ key: String) -> [T]
            }
            """,
            expandedSource: """
            protocol Cache {
                func get<T>(_ key: String) -> [T]
            }

            #if DEBUG
            class CacheMock: Cache {
                var getCallCount: Int = 0
                var getCallArgs: [String] = []
                var getHandler: (@Sendable (String) -> [Any])? = nil
                func get<T>(_ key: String) -> [T] {
                    getCallCount += 1
                    getCallArgs.append(key)
                    guard let _handler = getHandler else {
                        return []
                    }
                    return _handler(key) as! [T]
                }
                func resetMock() {
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
}
