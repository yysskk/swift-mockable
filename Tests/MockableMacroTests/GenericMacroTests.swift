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
                private(set) var getCallCount: Int = 0
                private(set) var getCallArguments: [String] = []
                var getHandler: ((String) -> Any)? = nil
                func get<T>(_ key: String) -> T {
                    getCallCount += 1
                    getCallArguments.append(key)
                    guard let _handler = getHandler else {
                        fatalError("\\(Self.self).getHandler is not set")
                    }
                    return _handler(key) as! T
                }
                func resetMock() {
                    getCallCount = 0
                    getCallArguments = []
                    getHandler = nil
                }
                class func resetMock() {
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
                private(set) var saveCallCount: Int = 0
                private(set) var saveCallArguments: [(value: Any, key: String)] = []
                var saveHandler: ((Any, String) -> Void)? = nil
                func save<T>(_ value: T, forKey key: String) {
                    saveCallCount += 1
                    saveCallArguments.append((value: value, key: key))
                    if let _handler = saveHandler {
                        _handler(value, key)
                    }
                }
                func resetMock() {
                    saveCallCount = 0
                    saveCallArguments = []
                    saveHandler = nil
                }
                class func resetMock() {
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
                private(set) var getCallCount: Int = 0
                private(set) var getCallArguments: [Any] = []
                var getHandler: ((Any) -> Any)? = nil
                func get<T>(_ key: UserDefaultsKey<T>) -> T {
                    getCallCount += 1
                    getCallArguments.append(key)
                    guard let _handler = getHandler else {
                        fatalError("\\(Self.self).getHandler is not set")
                    }
                    return _handler(key) as! T
                }
                private(set) var setCallCount: Int = 0
                private(set) var setCallArguments: [(value: Any, key: Any)] = []
                var setHandler: ((Any, Any) -> Void)? = nil
                func set<T>(_ value: T, forKey key: UserDefaultsKey<T>) {
                    setCallCount += 1
                    setCallArguments.append((value: value, key: key))
                    if let _handler = setHandler {
                        _handler(value, key)
                    }
                }
                func resetMock() {
                    getCallCount = 0
                    getCallArguments = []
                    getHandler = nil
                    setCallCount = 0
                    setCallArguments = []
                    setHandler = nil
                }
                class func resetMock() {
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
                private(set) var integerCallCount: Int = 0
                private(set) var integerCallArguments: [UserDefaultsKey<Int>] = []
                var integerHandler: ((UserDefaultsKey<Int>) -> Int)? = nil
                func integer(forKey key: UserDefaultsKey<Int>) -> Int {
                    integerCallCount += 1
                    integerCallArguments.append(key)
                    guard let _handler = integerHandler else {
                        fatalError("\\(Self.self).integerHandler is not set")
                    }
                    return _handler(key)
                }
                private(set) var setIntegerCallCount: Int = 0
                private(set) var setIntegerCallArguments: [(value: Int, key: UserDefaultsKey<Int>)] = []
                var setIntegerHandler: ((Int, UserDefaultsKey<Int>) -> Void)? = nil
                func setInteger(_ value: Int, forKey key: UserDefaultsKey<Int>) {
                    setIntegerCallCount += 1
                    setIntegerCallArguments.append((value: value, key: key))
                    if let _handler = setIntegerHandler {
                        _handler(value, key)
                    }
                }
                func resetMock() {
                    integerCallCount = 0
                    integerCallArguments = []
                    integerHandler = nil
                    setIntegerCallCount = 0
                    setIntegerCallArguments = []
                    setIntegerHandler = nil
                }
                class func resetMock() {
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
                private(set) var getCallCount: Int = 0
                private(set) var getCallArguments: [String] = []
                var getHandler: ((String) -> Any?)? = nil
                func get<T>(_ key: String) -> T? {
                    getCallCount += 1
                    getCallArguments.append(key)
                    guard let _handler = getHandler else {
                        return nil
                    }
                    return _handler(key) as! T?
                }
                func resetMock() {
                    getCallCount = 0
                    getCallArguments = []
                    getHandler = nil
                }
                class func resetMock() {
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
                private(set) var rewrapCallCount: Int = 0
                private(set) var rewrapCallArguments: [Any] = []
                var rewrapHandler: ((Any) -> Any)? = nil
                func rewrap<T>(_ box: Box<[T]>) -> Box<[T]> {
                    rewrapCallCount += 1
                    rewrapCallArguments.append(box)
                    guard let _handler = rewrapHandler else {
                        fatalError("\\(Self.self).rewrapHandler is not set")
                    }
                    return _handler(box) as! Box<[T]>
                }
                func resetMock() {
                    rewrapCallCount = 0
                    rewrapCallArguments = []
                    rewrapHandler = nil
                }
                class func resetMock() {
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
                private(set) var storeCallCount: Int = 0
                private(set) var storeCallArguments: [(box: Any, container: MyModule.Container)] = []
                var storeHandler: ((Any, MyModule.Container) -> Void)? = nil
                func store<T>(_ box: MyModule.Box<T>, in container: MyModule.Container) {
                    storeCallCount += 1
                    storeCallArguments.append((box: box, container: container))
                    if let _handler = storeHandler {
                        _handler(box, container)
                    }
                }
                func resetMock() {
                    storeCallCount = 0
                    storeCallArguments = []
                    storeHandler = nil
                }
                class func resetMock() {
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
                private(set) var firstElementCallCount: Int = 0
                private(set) var firstElementCallArguments: [Any] = []
                var firstElementHandler: ((Any) -> Any)? = nil
                func firstElement<T: Collection>(_ collection: T) -> T.Element {
                    firstElementCallCount += 1
                    firstElementCallArguments.append(collection)
                    guard let _handler = firstElementHandler else {
                        fatalError("\\(Self.self).firstElementHandler is not set")
                    }
                    return _handler(collection) as! T.Element
                }
                func resetMock() {
                    firstElementCallCount = 0
                    firstElementCallArguments = []
                    firstElementHandler = nil
                }
                class func resetMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Generic method with an existential or metatype erases it to Any")
    func genericExistentialAndMetatypeEraseToAny() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Cache {
                func decode<T>(_ type: T.Type) -> any Sequence<T>
            }
            """,
            expandedSource: """
            protocol Cache {
                func decode<T>(_ type: T.Type) -> any Sequence<T>
            }

            #if DEBUG
            class CacheMock: Cache {
                private(set) var decodeCallCount: Int = 0
                private(set) var decodeCallArguments: [Any] = []
                var decodeHandler: ((Any) -> Any)? = nil
                func decode<T>(_ type: T.Type) -> any Sequence<T> {
                    decodeCallCount += 1
                    decodeCallArguments.append(type)
                    guard let _handler = decodeHandler else {
                        fatalError("\\(Self.self).decodeHandler is not set")
                    }
                    return _handler(type) as! any Sequence<T>
                }
                func resetMock() {
                    decodeCallCount = 0
                    decodeCallArguments = []
                    decodeHandler = nil
                }
                class func resetMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Generic tuple return is erased in place and cast back")
    func genericTupleReturnErasesInPlace() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Cache {
                func pair<T>(_ key: String) -> (T, String)
            }
            """,
            expandedSource: """
            protocol Cache {
                func pair<T>(_ key: String) -> (T, String)
            }

            #if DEBUG
            class CacheMock: Cache {
                private(set) var pairCallCount: Int = 0
                private(set) var pairCallArguments: [String] = []
                var pairHandler: ((String) -> (Any, String))? = nil
                func pair<T>(_ key: String) -> (T, String) {
                    pairCallCount += 1
                    pairCallArguments.append(key)
                    guard let _handler = pairHandler else {
                        fatalError("\\(Self.self).pairHandler is not set")
                    }
                    return _handler(key) as! (T, String)
                }
                func resetMock() {
                    pairCallCount = 0
                    pairCallArguments = []
                    pairHandler = nil
                }
                class func resetMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Generic implicitly unwrapped optional return casts back as a regular optional")
    func genericImplicitlyUnwrappedOptionalReturnCastsAsOptional() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Cache {
                func get<T>(_ key: String) -> T!
            }
            """,
            expandedSource: """
            protocol Cache {
                func get<T>(_ key: String) -> T!
            }

            #if DEBUG
            class CacheMock: Cache {
                private(set) var getCallCount: Int = 0
                private(set) var getCallArguments: [String] = []
                var getHandler: ((String) -> Any?)? = nil
                func get<T>(_ key: String) -> T! {
                    getCallCount += 1
                    getCallArguments.append(key)
                    guard let _handler = getHandler else {
                        return nil
                    }
                    return _handler(key) as! T?
                }
                func resetMock() {
                    getCallCount = 0
                    getCallArguments = []
                    getHandler = nil
                }
                class func resetMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Generic method returning a closure is diagnosed as unsupported")
    func genericClosureReturnIsDiagnosed() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Cache {
                func makeSetter<T>() -> (T) -> Void
            }
            """,
            expandedSource: """
            protocol Cache {
                func makeSetter<T>() -> (T) -> Void
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: """
                        Cannot mock 'makeSetter': its return type '(T) -> Void' mentions a generic \
                        parameter inside a function type. The mock erases generic parameters in its \
                        handler and casts the result back, and Swift cannot convert between function \
                        types at runtime
                        """,
                    line: 3,
                    column: 5
                )
            ],
            macros: testMacros
        )
    }

    @Test("Erased closure inside an optional keeps its parentheses")
    func genericOptionalClosureParameterKeepsParentheses() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Cache {
                func load<T>(_ make: (() -> T)?)
            }
            """,
            expandedSource: """
            protocol Cache {
                func load<T>(_ make: (() -> T)?)
            }

            #if DEBUG
            class CacheMock: Cache {
                private(set) var loadCallCount: Int = 0
                private(set) var loadCallArguments: [(() -> Any)?] = []
                var loadHandler: (((() -> Any)?) -> Void)? = nil
                func load<T>(_ make: (() -> T)?) {
                    loadCallCount += 1
                    loadCallArguments.append(make)
                    if let _handler = loadHandler {
                        _handler(make)
                    }
                }
                func resetMock() {
                    loadCallCount = 0
                    loadCallArguments = []
                    loadHandler = nil
                }
                class func resetMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Attributed closure inside an optional keeps its parentheses")
    func attributedOptionalClosureParameterKeepsParentheses() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Cache {
                func load<T>(_ make: (@Sendable () -> T)?, fallback: (@Sendable () -> Int)?)
            }
            """,
            expandedSource: """
            protocol Cache {
                func load<T>(_ make: (@Sendable () -> T)?, fallback: (@Sendable () -> Int)?)
            }

            #if DEBUG
            class CacheMock: Cache {
                private(set) var loadCallCount: Int = 0
                private(set) var loadCallArguments: [(make: (@Sendable () -> Any)?, fallback: (@Sendable () -> Int)?)] = []
                var loadHandler: (((@Sendable () -> Any)?, (@Sendable () -> Int)?) -> Void)? = nil
                func load<T>(_ make: (@Sendable () -> T)?, fallback: (@Sendable () -> Int)?) {
                    loadCallCount += 1
                    loadCallArguments.append((make: make, fallback: fallback))
                    if let _handler = loadHandler {
                        _handler(make, fallback)
                    }
                }
                func resetMock() {
                    loadCallCount = 0
                    loadCallArguments = []
                    loadHandler = nil
                }
                class func resetMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Generic method taking a closure over a generic parameter is diagnosed as unsupported")
    func genericClosureParameterIsDiagnosed() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Cache {
                func observe<T>(_ handler: (T) -> Void)
            }
            """,
            expandedSource: """
            protocol Cache {
                func observe<T>(_ handler: (T) -> Void)
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: """
                        Cannot mock 'observe': the parameter 'handler' is a closure whose own parameters \
                        mention a generic parameter. The mock forwards it to a handler that erases generic \
                        parameters, and a closure taking '(T) -> Void' cannot be passed where one taking \
                        erased parameters is expected
                        """,
                    line: 3,
                    column: 21
                )
            ],
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
                private(set) var transformCallCount: Int = 0
                private(set) var transformCallArguments: [[String: Any]] = []
                var transformHandler: (([String: Any]) -> [String: Any])? = nil
                func transform<T>(_ map: [String: T]) -> [String: T] {
                    transformCallCount += 1
                    transformCallArguments.append(map)
                    guard let _handler = transformHandler else {
                        return [:]
                    }
                    return _handler(map) as! [String: T]
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
                private(set) var indexCallCount: Int = 0
                private(set) var indexCallArguments: [Any] = []
                var indexHandler: ((Any) -> Any)? = nil
                func index<T: Hashable>(_ map: [T: String]) -> [T: String] {
                    indexCallCount += 1
                    indexCallArguments.append(map)
                    guard let _handler = indexHandler else {
                        return [:]
                    }
                    return _handler(map) as! [T: String]
                }
                func resetMock() {
                    indexCallCount = 0
                    indexCallArguments = []
                    indexHandler = nil
                }
                class func resetMock() {
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
                private(set) var lookupCallCount: Int = 0
                private(set) var lookupCallArguments: [[String: [Any]]?] = []
                var lookupHandler: (([String: [Any]]?) -> [String: Any]?)? = nil
                func lookup<T>(_ map: [String: [T]]?) -> [String: T]? {
                    lookupCallCount += 1
                    lookupCallArguments.append(map)
                    guard let _handler = lookupHandler else {
                        return nil
                    }
                    return _handler(map) as! [String: T]?
                }
                func resetMock() {
                    lookupCallCount = 0
                    lookupCallArguments = []
                    lookupHandler = nil
                }
                class func resetMock() {
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
                private(set) var storeCallCount: Int = 0
                private(set) var storeCallArguments: [(value: Any, metadata: [String: Int])] = []
                var storeHandler: ((Any, [String: Int]) -> Void)? = nil
                func store<T>(_ value: T, metadata: [String: Int]) {
                    storeCallCount += 1
                    storeCallArguments.append((value: value, metadata: metadata))
                    if let _handler = storeHandler {
                        _handler(value, metadata)
                    }
                }
                func resetMock() {
                    storeCallCount = 0
                    storeCallArguments = []
                    storeHandler = nil
                }
                class func resetMock() {
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
                private(set) var getCallCount: Int = 0
                private(set) var getCallArguments: [String] = []
                var getHandler: ((String) -> [Any])? = nil
                func get<T>(_ key: String) -> [T] {
                    getCallCount += 1
                    getCallArguments.append(key)
                    guard let _handler = getHandler else {
                        return []
                    }
                    return _handler(key) as! [T]
                }
                func resetMock() {
                    getCallCount = 0
                    getCallArguments = []
                    getHandler = nil
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
