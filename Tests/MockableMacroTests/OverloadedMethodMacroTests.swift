import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import MockableMacros

@Suite("Overloaded Method Macro Tests")
struct OverloadedMethodMacroTests {
    private let testMacros: [String: Macro.Type] = [
        "Mockable": MockableMacro.self
    ]

    @Test("Protocol with overloaded methods generates unique property names")
    func overloadedMethods() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol UserDefaults {
                func set(_ value: Bool, forKey: String)
                func set(_ value: Int, forKey: String)
                func set(_ value: String, forKey: String)
                func getValue() -> String
            }
            """,
            expandedSource: """
            protocol UserDefaults {
                func set(_ value: Bool, forKey: String)
                func set(_ value: Int, forKey: String)
                func set(_ value: String, forKey: String)
                func getValue() -> String
            }

            #if DEBUG
            class UserDefaultsMock: UserDefaults {
                private(set) var setBoolStringCallCount: Int = 0
                private(set) var setBoolStringCallArguments: [(value: Bool, forKey: String)] = []
                var setBoolStringHandler: ((Bool, String) -> Void)? = nil
                func set(_ value: Bool, forKey: String) {
                    setBoolStringCallCount += 1
                    setBoolStringCallArguments.append((value: value, forKey: forKey))
                    if let _handler = setBoolStringHandler {
                        _handler(value, forKey)
                    }
                }
                private(set) var setIntStringCallCount: Int = 0
                private(set) var setIntStringCallArguments: [(value: Int, forKey: String)] = []
                var setIntStringHandler: ((Int, String) -> Void)? = nil
                func set(_ value: Int, forKey: String) {
                    setIntStringCallCount += 1
                    setIntStringCallArguments.append((value: value, forKey: forKey))
                    if let _handler = setIntStringHandler {
                        _handler(value, forKey)
                    }
                }
                private(set) var setStringStringCallCount: Int = 0
                private(set) var setStringStringCallArguments: [(value: String, forKey: String)] = []
                var setStringStringHandler: ((String, String) -> Void)? = nil
                func set(_ value: String, forKey: String) {
                    setStringStringCallCount += 1
                    setStringStringCallArguments.append((value: value, forKey: forKey))
                    if let _handler = setStringStringHandler {
                        _handler(value, forKey)
                    }
                }
                private(set) var getValueCallCount: Int = 0
                @available(*, deprecated, message: "getValue records no arguments; use getValueCallCount instead.")
                var getValueCallArguments: [()] {
                    Array(repeating: (), count: getValueCallCount)
                }
                var getValueHandler: (() -> String)? = nil
                func getValue() -> String {
                    getValueCallCount += 1
                    guard let _handler = getValueHandler else {
                        fatalError("\\(Self.self).getValueHandler is not set")
                    }
                    return _handler()
                }
                func resetMock() {
                    setBoolStringCallCount = 0
                    setBoolStringCallArguments = []
                    setBoolStringHandler = nil
                    setIntStringCallCount = 0
                    setIntStringCallArguments = []
                    setIntStringHandler = nil
                    setStringStringCallCount = 0
                    setStringStringCallArguments = []
                    setStringStringHandler = nil
                    getValueCallCount = 0
                    getValueHandler = nil
                }
                class func resetStaticMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol without overloads keeps simple naming")
    func noOverloads() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol SimpleService {
                func fetchData(id: Int) -> String
                func saveData(data: String)
            }
            """,
            expandedSource: """
            protocol SimpleService {
                func fetchData(id: Int) -> String
                func saveData(data: String)
            }

            #if DEBUG
            class SimpleServiceMock: SimpleService {
                private(set) var fetchDataCallCount: Int = 0
                private(set) var fetchDataCallArguments: [Int] = []
                var fetchDataHandler: ((Int) -> String)? = nil
                func fetchData(id: Int) -> String {
                    fetchDataCallCount += 1
                    fetchDataCallArguments.append(id)
                    guard let _handler = fetchDataHandler else {
                        fatalError("\\(Self.self).fetchDataHandler is not set")
                    }
                    return _handler(id)
                }
                private(set) var saveDataCallCount: Int = 0
                private(set) var saveDataCallArguments: [String] = []
                var saveDataHandler: ((String) -> Void)? = nil
                func saveData(data: String) {
                    saveDataCallCount += 1
                    saveDataCallArguments.append(data)
                    if let _handler = saveDataHandler {
                        _handler(data)
                    }
                }
                func resetMock() {
                    fetchDataCallCount = 0
                    fetchDataCallArguments = []
                    fetchDataHandler = nil
                    saveDataCallCount = 0
                    saveDataCallArguments = []
                    saveDataHandler = nil
                }
                class func resetStaticMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Overloaded methods with same parameter types but different return types generate unique suffixes")
    func overloadedMethodsSameParamsDifferentReturnTypes() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol HttpService {
                func get(url: String) -> String
                func get(url: String) throws -> Data
            }
            """,
            expandedSource: """
            protocol HttpService {
                func get(url: String) -> String
                func get(url: String) throws -> Data
            }

            #if DEBUG
            class HttpServiceMock: HttpService {
                private(set) var getStringStringCallCount: Int = 0
                private(set) var getStringStringCallArguments: [String] = []
                var getStringStringHandler: ((String) -> String)? = nil
                func get(url: String) -> String {
                    getStringStringCallCount += 1
                    getStringStringCallArguments.append(url)
                    guard let _handler = getStringStringHandler else {
                        fatalError("\\(Self.self).getStringStringHandler is not set")
                    }
                    return _handler(url)
                }
                private(set) var getStringDataThrowingCallCount: Int = 0
                private(set) var getStringDataThrowingCallArguments: [String] = []
                var getStringDataThrowingHandler: ((String) throws -> Data)? = nil
                func get(url: String) throws -> Data {
                    getStringDataThrowingCallCount += 1
                    getStringDataThrowingCallArguments.append(url)
                    guard let _handler = getStringDataThrowingHandler else {
                        fatalError("\\(Self.self).getStringDataThrowingHandler is not set")
                    }
                    return try _handler(url)
                }
                func resetMock() {
                    getStringStringCallCount = 0
                    getStringStringCallArguments = []
                    getStringStringHandler = nil
                    getStringDataThrowingCallCount = 0
                    getStringDataThrowingCallArguments = []
                    getStringDataThrowingHandler = nil
                }
                class func resetStaticMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Overloaded methods with same parameter types but different async/throws modifiers generate unique suffixes")
    func overloadedMethodsSameParamsDifferentModifiers() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol DataService {
                func fetch(id: Int) -> String
                func fetch(id: Int) async -> String
                func fetch(id: Int) async throws -> String
            }
            """,
            expandedSource: """
            protocol DataService {
                func fetch(id: Int) -> String
                func fetch(id: Int) async -> String
                func fetch(id: Int) async throws -> String
            }

            #if DEBUG
            class DataServiceMock: DataService {
                private(set) var fetchIntStringCallCount: Int = 0
                private(set) var fetchIntStringCallArguments: [Int] = []
                var fetchIntStringHandler: ((Int) -> String)? = nil
                func fetch(id: Int) -> String {
                    fetchIntStringCallCount += 1
                    fetchIntStringCallArguments.append(id)
                    guard let _handler = fetchIntStringHandler else {
                        fatalError("\\(Self.self).fetchIntStringHandler is not set")
                    }
                    return _handler(id)
                }
                private(set) var fetchIntStringAsyncCallCount: Int = 0
                private(set) var fetchIntStringAsyncCallArguments: [Int] = []
                var fetchIntStringAsyncHandler: ((Int) async -> String)? = nil
                func fetch(id: Int) async -> String {
                    fetchIntStringAsyncCallCount += 1
                    fetchIntStringAsyncCallArguments.append(id)
                    guard let _handler = fetchIntStringAsyncHandler else {
                        fatalError("\\(Self.self).fetchIntStringAsyncHandler is not set")
                    }
                    return await _handler(id)
                }
                private(set) var fetchIntStringAsyncThrowingCallCount: Int = 0
                private(set) var fetchIntStringAsyncThrowingCallArguments: [Int] = []
                var fetchIntStringAsyncThrowingHandler: ((Int) async throws -> String)? = nil
                func fetch(id: Int) async throws -> String {
                    fetchIntStringAsyncThrowingCallCount += 1
                    fetchIntStringAsyncThrowingCallArguments.append(id)
                    guard let _handler = fetchIntStringAsyncThrowingHandler else {
                        fatalError("\\(Self.self).fetchIntStringAsyncThrowingHandler is not set")
                    }
                    return try await _handler(id)
                }
                func resetMock() {
                    fetchIntStringCallCount = 0
                    fetchIntStringCallArguments = []
                    fetchIntStringHandler = nil
                    fetchIntStringAsyncCallCount = 0
                    fetchIntStringAsyncCallArguments = []
                    fetchIntStringAsyncHandler = nil
                    fetchIntStringAsyncThrowingCallCount = 0
                    fetchIntStringAsyncThrowingCallArguments = []
                    fetchIntStringAsyncThrowingHandler = nil
                }
                class func resetStaticMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Mixed overloaded methods - some with same params, some with different params")
    func mixedOverloadedMethods() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol MixedService {
                func process(value: Int) -> String
                func process(value: Int) throws -> Data
                func process(value: String) -> String
            }
            """,
            expandedSource: """
            protocol MixedService {
                func process(value: Int) -> String
                func process(value: Int) throws -> Data
                func process(value: String) -> String
            }

            #if DEBUG
            class MixedServiceMock: MixedService {
                private(set) var processIntStringCallCount: Int = 0
                private(set) var processIntStringCallArguments: [Int] = []
                var processIntStringHandler: ((Int) -> String)? = nil
                func process(value: Int) -> String {
                    processIntStringCallCount += 1
                    processIntStringCallArguments.append(value)
                    guard let _handler = processIntStringHandler else {
                        fatalError("\\(Self.self).processIntStringHandler is not set")
                    }
                    return _handler(value)
                }
                private(set) var processIntDataThrowingCallCount: Int = 0
                private(set) var processIntDataThrowingCallArguments: [Int] = []
                var processIntDataThrowingHandler: ((Int) throws -> Data)? = nil
                func process(value: Int) throws -> Data {
                    processIntDataThrowingCallCount += 1
                    processIntDataThrowingCallArguments.append(value)
                    guard let _handler = processIntDataThrowingHandler else {
                        fatalError("\\(Self.self).processIntDataThrowingHandler is not set")
                    }
                    return try _handler(value)
                }
                private(set) var processStringCallCount: Int = 0
                private(set) var processStringCallArguments: [String] = []
                var processStringHandler: ((String) -> String)? = nil
                func process(value: String) -> String {
                    processStringCallCount += 1
                    processStringCallArguments.append(value)
                    guard let _handler = processStringHandler else {
                        fatalError("\\(Self.self).processStringHandler is not set")
                    }
                    return _handler(value)
                }
                func resetMock() {
                    processIntStringCallCount = 0
                    processIntStringCallArguments = []
                    processIntStringHandler = nil
                    processIntDataThrowingCallCount = 0
                    processIntDataThrowingCallArguments = []
                    processIntDataThrowingHandler = nil
                    processStringCallCount = 0
                    processStringCallArguments = []
                    processStringHandler = nil
                }
                class func resetStaticMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Overloads whose sanitized suffixes collide are disambiguated with an ordinal")
    func collidingSuffixesGetOrdinal() {
        // `Pair<A, B>` and `Pair<AB>` both sanitize to `PairAB`, and both overloads
        // are void/sync so the extended suffix collides too. The second overload gets
        // a deterministic source-order ordinal to keep generated names unique.
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Handler {
                func handle(_ value: Pair<A, B>)
                func handle(_ value: Pair<AB>)
            }
            """,
            expandedSource: """
            protocol Handler {
                func handle(_ value: Pair<A, B>)
                func handle(_ value: Pair<AB>)
            }

            #if DEBUG
            class HandlerMock: Handler {
                private(set) var handlePairABCallCount: Int = 0
                private(set) var handlePairABCallArguments: [Pair<A, B>] = []
                var handlePairABHandler: ((Pair<A, B>) -> Void)? = nil
                func handle(_ value: Pair<A, B>) {
                    handlePairABCallCount += 1
                    handlePairABCallArguments.append(value)
                    if let _handler = handlePairABHandler {
                        _handler(value)
                    }
                }
                private(set) var handlePairAB2CallCount: Int = 0
                private(set) var handlePairAB2CallArguments: [Pair<AB>] = []
                var handlePairAB2Handler: ((Pair<AB>) -> Void)? = nil
                func handle(_ value: Pair<AB>) {
                    handlePairAB2CallCount += 1
                    handlePairAB2CallArguments.append(value)
                    if let _handler = handlePairAB2Handler {
                        _handler(value)
                    }
                }
                func resetMock() {
                    handlePairABCallCount = 0
                    handlePairABCallArguments = []
                    handlePairABHandler = nil
                    handlePairAB2CallCount = 0
                    handlePairAB2CallArguments = []
                    handlePairAB2Handler = nil
                }
                class func resetStaticMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Overloads are named after their argument labels, with types for those that share labels")
    func overloadsNamedAfterArgumentLabels() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol UserStore {
                func fetch(id: Int) -> String
                func fetch(name: String) -> String
                func save(_ user: String)
                func save(_ users: [String])
            }
            """,
            expandedSource: """
            protocol UserStore {
                func fetch(id: Int) -> String
                func fetch(name: String) -> String
                func save(_ user: String)
                func save(_ users: [String])
            }

            #if DEBUG
            class UserStoreMock: UserStore {
                private(set) var fetchIDCallCount: Int = 0
                private(set) var fetchIDCallArguments: [Int] = []
                var fetchIDHandler: ((Int) -> String)? = nil
                func fetch(id: Int) -> String {
                    fetchIDCallCount += 1
                    fetchIDCallArguments.append(id)
                    guard let _handler = fetchIDHandler else {
                        fatalError("\\(Self.self).fetchIDHandler is not set")
                    }
                    return _handler(id)
                }
                private(set) var fetchNameCallCount: Int = 0
                private(set) var fetchNameCallArguments: [String] = []
                var fetchNameHandler: ((String) -> String)? = nil
                func fetch(name: String) -> String {
                    fetchNameCallCount += 1
                    fetchNameCallArguments.append(name)
                    guard let _handler = fetchNameHandler else {
                        fatalError("\\(Self.self).fetchNameHandler is not set")
                    }
                    return _handler(name)
                }
                private(set) var saveStringCallCount: Int = 0
                private(set) var saveStringCallArguments: [String] = []
                var saveStringHandler: ((String) -> Void)? = nil
                func save(_ user: String) {
                    saveStringCallCount += 1
                    saveStringCallArguments.append(user)
                    if let _handler = saveStringHandler {
                        _handler(user)
                    }
                }
                private(set) var saveStringArrayCallCount: Int = 0
                private(set) var saveStringArrayCallArguments: [[String]] = []
                var saveStringArrayHandler: (([String]) -> Void)? = nil
                func save(_ users: [String]) {
                    saveStringArrayCallCount += 1
                    saveStringArrayCallArguments.append(users)
                    if let _handler = saveStringArrayHandler {
                        _handler(users)
                    }
                }
                func resetMock() {
                    fetchIDCallCount = 0
                    fetchIDCallArguments = []
                    fetchIDHandler = nil
                    fetchNameCallCount = 0
                    fetchNameCallArguments = []
                    fetchNameHandler = nil
                    saveStringCallCount = 0
                    saveStringCallArguments = []
                    saveStringHandler = nil
                    saveStringArrayCallCount = 0
                    saveStringArrayCallArguments = []
                    saveStringArrayHandler = nil
                }
                class func resetStaticMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }
}
