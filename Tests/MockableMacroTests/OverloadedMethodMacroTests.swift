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
            public class UserDefaultsMock: UserDefaults {
                public var setBoolStringCallCount: Int = 0
                public var setBoolStringCallArgs: [(value: Bool, forKey: String)] = []
                public var setBoolStringHandler: (@Sendable ((value: Bool, forKey: String)) -> Void)? = nil
                public func set(_ value: Bool, forKey: String) {
                    setBoolStringCallCount += 1
                    setBoolStringCallArgs.append((value: value, forKey: forKey))
                    if let _handler = setBoolStringHandler {
                        _handler((value: value, forKey: forKey))
                    }
                }
                public var setIntStringCallCount: Int = 0
                public var setIntStringCallArgs: [(value: Int, forKey: String)] = []
                public var setIntStringHandler: (@Sendable ((value: Int, forKey: String)) -> Void)? = nil
                public func set(_ value: Int, forKey: String) {
                    setIntStringCallCount += 1
                    setIntStringCallArgs.append((value: value, forKey: forKey))
                    if let _handler = setIntStringHandler {
                        _handler((value: value, forKey: forKey))
                    }
                }
                public var setStringStringCallCount: Int = 0
                public var setStringStringCallArgs: [(value: String, forKey: String)] = []
                public var setStringStringHandler: (@Sendable ((value: String, forKey: String)) -> Void)? = nil
                public func set(_ value: String, forKey: String) {
                    setStringStringCallCount += 1
                    setStringStringCallArgs.append((value: value, forKey: forKey))
                    if let _handler = setStringStringHandler {
                        _handler((value: value, forKey: forKey))
                    }
                }
                public var getValueCallCount: Int = 0
                public var getValueCallArgs: [()] = []
                public var getValueHandler: (@Sendable () -> String)? = nil
                public func getValue() -> String {
                    getValueCallCount += 1
                    getValueCallArgs.append(())
                    guard let _handler = getValueHandler else {
                        fatalError("\\(Self.self).getValueHandler is not set")
                    }
                    return _handler()
                }
                public func resetMock() {
                    setBoolStringCallCount = 0
                    setBoolStringCallArgs = []
                    setBoolStringHandler = nil
                    setIntStringCallCount = 0
                    setIntStringCallArgs = []
                    setIntStringHandler = nil
                    setStringStringCallCount = 0
                    setStringStringCallArgs = []
                    setStringStringHandler = nil
                    getValueCallCount = 0
                    getValueCallArgs = []
                    getValueHandler = nil
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
            public class SimpleServiceMock: SimpleService {
                public var fetchDataCallCount: Int = 0
                public var fetchDataCallArgs: [Int] = []
                public var fetchDataHandler: (@Sendable (Int) -> String)? = nil
                public func fetchData(id: Int) -> String {
                    fetchDataCallCount += 1
                    fetchDataCallArgs.append(id)
                    guard let _handler = fetchDataHandler else {
                        fatalError("\\(Self.self).fetchDataHandler is not set")
                    }
                    return _handler(id)
                }
                public var saveDataCallCount: Int = 0
                public var saveDataCallArgs: [String] = []
                public var saveDataHandler: (@Sendable (String) -> Void)? = nil
                public func saveData(data: String) {
                    saveDataCallCount += 1
                    saveDataCallArgs.append(data)
                    if let _handler = saveDataHandler {
                        _handler(data)
                    }
                }
                public func resetMock() {
                    fetchDataCallCount = 0
                    fetchDataCallArgs = []
                    fetchDataHandler = nil
                    saveDataCallCount = 0
                    saveDataCallArgs = []
                    saveDataHandler = nil
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
            public class HttpServiceMock: HttpService {
                public var getStringStringCallCount: Int = 0
                public var getStringStringCallArgs: [String] = []
                public var getStringStringHandler: (@Sendable (String) -> String)? = nil
                public func get(url: String) -> String {
                    getStringStringCallCount += 1
                    getStringStringCallArgs.append(url)
                    guard let _handler = getStringStringHandler else {
                        fatalError("\\(Self.self).getStringStringHandler is not set")
                    }
                    return _handler(url)
                }
                public var getStringDataThrowingCallCount: Int = 0
                public var getStringDataThrowingCallArgs: [String] = []
                public var getStringDataThrowingHandler: (@Sendable (String) throws -> Data)? = nil
                public func get(url: String) throws -> Data {
                    getStringDataThrowingCallCount += 1
                    getStringDataThrowingCallArgs.append(url)
                    guard let _handler = getStringDataThrowingHandler else {
                        fatalError("\\(Self.self).getStringDataThrowingHandler is not set")
                    }
                    return try _handler(url)
                }
                public func resetMock() {
                    getStringStringCallCount = 0
                    getStringStringCallArgs = []
                    getStringStringHandler = nil
                    getStringDataThrowingCallCount = 0
                    getStringDataThrowingCallArgs = []
                    getStringDataThrowingHandler = nil
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
            public class DataServiceMock: DataService {
                public var fetchIntStringCallCount: Int = 0
                public var fetchIntStringCallArgs: [Int] = []
                public var fetchIntStringHandler: (@Sendable (Int) -> String)? = nil
                public func fetch(id: Int) -> String {
                    fetchIntStringCallCount += 1
                    fetchIntStringCallArgs.append(id)
                    guard let _handler = fetchIntStringHandler else {
                        fatalError("\\(Self.self).fetchIntStringHandler is not set")
                    }
                    return _handler(id)
                }
                public var fetchIntStringAsyncCallCount: Int = 0
                public var fetchIntStringAsyncCallArgs: [Int] = []
                public var fetchIntStringAsyncHandler: (@Sendable (Int) async -> String)? = nil
                public func fetch(id: Int) async -> String {
                    fetchIntStringAsyncCallCount += 1
                    fetchIntStringAsyncCallArgs.append(id)
                    guard let _handler = fetchIntStringAsyncHandler else {
                        fatalError("\\(Self.self).fetchIntStringAsyncHandler is not set")
                    }
                    return await _handler(id)
                }
                public var fetchIntStringAsyncThrowingCallCount: Int = 0
                public var fetchIntStringAsyncThrowingCallArgs: [Int] = []
                public var fetchIntStringAsyncThrowingHandler: (@Sendable (Int) async throws -> String)? = nil
                public func fetch(id: Int) async throws -> String {
                    fetchIntStringAsyncThrowingCallCount += 1
                    fetchIntStringAsyncThrowingCallArgs.append(id)
                    guard let _handler = fetchIntStringAsyncThrowingHandler else {
                        fatalError("\\(Self.self).fetchIntStringAsyncThrowingHandler is not set")
                    }
                    return try await _handler(id)
                }
                public func resetMock() {
                    fetchIntStringCallCount = 0
                    fetchIntStringCallArgs = []
                    fetchIntStringHandler = nil
                    fetchIntStringAsyncCallCount = 0
                    fetchIntStringAsyncCallArgs = []
                    fetchIntStringAsyncHandler = nil
                    fetchIntStringAsyncThrowingCallCount = 0
                    fetchIntStringAsyncThrowingCallArgs = []
                    fetchIntStringAsyncThrowingHandler = nil
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
            public class MixedServiceMock: MixedService {
                public var processIntStringCallCount: Int = 0
                public var processIntStringCallArgs: [Int] = []
                public var processIntStringHandler: (@Sendable (Int) -> String)? = nil
                public func process(value: Int) -> String {
                    processIntStringCallCount += 1
                    processIntStringCallArgs.append(value)
                    guard let _handler = processIntStringHandler else {
                        fatalError("\\(Self.self).processIntStringHandler is not set")
                    }
                    return _handler(value)
                }
                public var processIntDataThrowingCallCount: Int = 0
                public var processIntDataThrowingCallArgs: [Int] = []
                public var processIntDataThrowingHandler: (@Sendable (Int) throws -> Data)? = nil
                public func process(value: Int) throws -> Data {
                    processIntDataThrowingCallCount += 1
                    processIntDataThrowingCallArgs.append(value)
                    guard let _handler = processIntDataThrowingHandler else {
                        fatalError("\\(Self.self).processIntDataThrowingHandler is not set")
                    }
                    return try _handler(value)
                }
                public var processStringCallCount: Int = 0
                public var processStringCallArgs: [String] = []
                public var processStringHandler: (@Sendable (String) -> String)? = nil
                public func process(value: String) -> String {
                    processStringCallCount += 1
                    processStringCallArgs.append(value)
                    guard let _handler = processStringHandler else {
                        fatalError("\\(Self.self).processStringHandler is not set")
                    }
                    return _handler(value)
                }
                public func resetMock() {
                    processIntStringCallCount = 0
                    processIntStringCallArgs = []
                    processIntStringHandler = nil
                    processIntDataThrowingCallCount = 0
                    processIntDataThrowingCallArgs = []
                    processIntDataThrowingHandler = nil
                    processStringCallCount = 0
                    processStringCallArgs = []
                    processStringHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }
}
