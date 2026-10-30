import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import MockableMacros

@Suite("Typed Throws Macro Tests")
struct TypedThrowsMacroTests {
    private let testMacros: [String: Macro.Type] = [
        "Mockable": MockableMacro.self
    ]

    @Test("typed throws method re-throws the typed error from an untyped handler")
    func typedThrowsMethodReThrowsTypedError() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Loader {
                func load(id: Int) throws(LoadError) -> String
            }
            """,
            expandedSource: """
            protocol Loader {
                func load(id: Int) throws(LoadError) -> String
            }

            #if DEBUG
            class LoaderMock: Loader {
                private(set) var loadCallCount: Int = 0
                private(set) var loadCallArguments: [Int] = []
                var loadHandler: ((Int) throws -> String)? = nil
                func load(id: Int) throws(LoadError) -> String {
                    loadCallCount += 1
                    loadCallArguments.append(id)
                    guard let _handler = loadHandler else {
                        fatalError("\\(Self.self).loadHandler is not set")
                    }
                    do {
                        return try _handler(id)
                    } catch {
                        throw error as! LoadError
                    }
                }
                func resetMock() {
                    loadCallCount = 0
                    loadCallArguments = []
                    loadHandler = nil
                }
                class func resetStaticMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("typed throws async method wraps the awaited handler call")
    func typedThrowsAsyncMethodWrapsAwaitedCall() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Fetcher {
                func fetch() async throws(NetworkError) -> Data
            }
            """,
            expandedSource: """
            protocol Fetcher {
                func fetch() async throws(NetworkError) -> Data
            }

            #if DEBUG
            class FetcherMock: Fetcher {
                private(set) var fetchCallCount: Int = 0
                @available(*, deprecated, message: "fetch records no arguments; use fetchCallCount instead.")
                var fetchCallArguments: [()] {
                    Array(repeating: (), count: fetchCallCount)
                }
                var fetchHandler: (() async throws -> Data)? = nil
                func fetch() async throws(NetworkError) -> Data {
                    fetchCallCount += 1
                    guard let _handler = fetchHandler else {
                        fatalError("\\(Self.self).fetchHandler is not set")
                    }
                    do {
                        return try await _handler()
                    } catch {
                        throw error as! NetworkError
                    }
                }
                func resetMock() {
                    fetchCallCount = 0
                    fetchHandler = nil
                }
                class func resetStaticMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("generic typed throws error type is used only in the body, not the stored handler")
    func genericTypedThrowsErrorType() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Runner {
                func run<E: Error>(_ body: () throws(E) -> Void) throws(E)
            }
            """,
            expandedSource: """
            protocol Runner {
                func run<E: Error>(_ body: () throws(E) -> Void) throws(E)
            }

            #if DEBUG
            class RunnerMock: Runner {
                private(set) var runCallCount: Int = 0
                @available(*, deprecated, message: "run records no arguments; use runCallCount instead.")
                var runCallArguments: [()] {
                    Array(repeating: (), count: runCallCount)
                }
                var runHandler: ((() throws -> Void) throws -> Void)? = nil
                func run<E: Error>(_ body: () throws(E) -> Void) throws(E) {
                    runCallCount += 1
                    if let _handler = runHandler {
                        do {
                            try _handler(body)
                        } catch {
                            throw error as! E
                        }
                    }
                }
                func resetMock() {
                    runCallCount = 0
                    runHandler = nil
                }
                class func resetStaticMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("concrete typed-throws closure parameter is stored with an untyped throws clause")
    func concreteTypedThrowsClosureParameterIsErased() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Runner {
                func run(_ body: @escaping () throws(RunError) -> Void)
            }
            """,
            expandedSource: """
            protocol Runner {
                func run(_ body: @escaping () throws(RunError) -> Void)
            }

            #if DEBUG
            class RunnerMock: Runner {
                private(set) var runCallCount: Int = 0
                private(set) var runCallArguments: [() throws -> Void] = []
                var runHandler: ((() throws -> Void) -> Void)? = nil
                func run(_ body: @escaping () throws(RunError) -> Void) {
                    runCallCount += 1
                    runCallArguments.append(body)
                    if let _handler = runHandler {
                        _handler(body)
                    }
                }
                func resetMock() {
                    runCallCount = 0
                    runCallArguments = []
                    runHandler = nil
                }
                class func resetStaticMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("typed throws method converts a throwing @autoclosure error too")
    func typedThrowsMethodConvertsAutoclosureError() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Calculator {
                func compute(_ value: @autoclosure () throws -> Int) throws(ComputeError) -> Int
            }
            """,
            expandedSource: """
            protocol Calculator {
                func compute(_ value: @autoclosure () throws -> Int) throws(ComputeError) -> Int
            }

            #if DEBUG
            class CalculatorMock: Calculator {
                private(set) var computeCallCount: Int = 0
                private(set) var computeCallArguments: [Int] = []
                var computeHandler: ((Int) throws -> Int)? = nil
                func compute(_ value: @autoclosure () throws -> Int) throws(ComputeError) -> Int {
                    do {
                        let value = try value()
                        computeCallCount += 1
                        computeCallArguments.append(value)
                        guard let _handler = computeHandler else {
                            fatalError("\\(Self.self).computeHandler is not set")
                        }
                        return try _handler(value)
                    } catch {
                        throw error as! ComputeError
                    }
                }
                func resetMock() {
                    computeCallCount = 0
                    computeCallArguments = []
                    computeHandler = nil
                }
                class func resetStaticMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Sendable typed throws method evaluates a throwing @autoclosure before locking")
    func sendableTypedThrowsMethodConvertsAutoclosureError() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Calculator: Sendable {
                func compute(_ value: @autoclosure @Sendable () throws -> Int) throws(ComputeError) -> Int
            }
            """,
            expandedSource: """
            protocol Calculator: Sendable {
                func compute(_ value: @autoclosure @Sendable () throws -> Int) throws(ComputeError) -> Int
            }

            #if DEBUG
            class CalculatorMock: Calculator, @unchecked Sendable {
                private struct Storage {
                    var computeCallCount: Int = 0
                    var computeCallArguments: [Int] = []
                    var computeHandler: (@Sendable (Int) throws -> Int)? = nil
                }
                private let _storage = MockableLock<Storage>(Storage())
                var computeCallCount: Int {
                    _storage.withLock {
                        $0.computeCallCount
                    }
                }
                var computeCallArguments: [Int] {
                    _storage.withLock {
                        $0.computeCallArguments
                    }
                }
                var computeHandler: (@Sendable (Int) throws -> Int)? {
                    get {
                        _storage.withLock {
                            $0.computeHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.computeHandler = newValue
                        }
                    }
                }
                func compute(_ value: @autoclosure @Sendable () throws -> Int) throws(ComputeError) -> Int {
                    do {
                        let value = try value()
                        let _handler = _storage.withLock { storage -> (@Sendable (Int) throws -> Int)? in
                            storage.computeCallCount += 1
                            storage.computeCallArguments.append(value)
                            return storage.computeHandler
                        }
                        guard let _handler else {
                            fatalError("\\(Self.self).computeHandler is not set")
                        }
                        return try _handler(value)
                    } catch {
                        throw error as! ComputeError
                    }
                }
                func resetMock() {
                    _storage.withLock { storage in
                        storage.computeCallCount = 0
                        storage.computeCallArguments = []
                        storage.computeHandler = nil
                    }
                }
                class func resetStaticMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("typed throws init requirement converts a throwing @autoclosure error")
    func typedThrowsInitializerConvertsAutoclosureError() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Builder {
                init(_ value: @autoclosure () throws -> Int) throws(SetupError)
            }
            """,
            expandedSource: """
            protocol Builder {
                init(_ value: @autoclosure () throws -> Int) throws(SetupError)
            }

            #if DEBUG
            class BuilderMock: Builder {
                private(set) var initCallCount: Int = 0
                private(set) var initCallArguments: [Int] = []
                required init(_ value: @autoclosure () throws -> Int) throws(SetupError) {
                    do {
                        let value = try value()
                        initCallCount += 1
                        initCallArguments.append(value)
                    } catch {
                        throw error as! SetupError
                    }
                }
                func resetMock() {
                    initCallCount = 0
                    initCallArguments = []
                }
                class func resetStaticMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("typed throws subscript re-throws the typed error")
    func typedThrowsSubscriptReThrowsTypedError() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Catalog {
                subscript(id: Int) -> String { get throws(LookupError) }
            }
            """,
            expandedSource: """
            protocol Catalog {
                subscript(id: Int) -> String { get throws(LookupError) }
            }

            #if DEBUG
            class CatalogMock: Catalog {
                private(set) var subscriptIntCallCount: Int = 0
                private(set) var subscriptIntCallArguments: [Int] = []
                var subscriptIntHandler: ((Int) throws -> String )? = nil
                subscript(id: Int) -> String {
                    get throws(LookupError) {
                        subscriptIntCallCount += 1
                        subscriptIntCallArguments.append(id)
                        guard let _handler = subscriptIntHandler else {
                            fatalError("\\(Self.self).subscriptIntHandler is not set")
                        }
                        do {
                            return try _handler(id)
                        } catch {
                            throw error as! LookupError
                        }
                    }
                }
                func resetMock() {
                    subscriptIntCallCount = 0
                    subscriptIntCallArguments = []
                    subscriptIntHandler = nil
                }
                class func resetStaticMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("typed throws init requirement keeps its signature and records the call")
    func typedThrowsInitializerKeepsSignature() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Repository {
                init(id: String) throws(SetupError)
            }
            """,
            expandedSource: """
            protocol Repository {
                init(id: String) throws(SetupError)
            }

            #if DEBUG
            class RepositoryMock: Repository {
                private(set) var initCallCount: Int = 0
                private(set) var initCallArguments: [String] = []
                required init(id: String) throws(SetupError) {
                    initCallCount += 1
                    initCallArguments.append(id)
                }
                func resetMock() {
                    initCallCount = 0
                    initCallArguments = []
                }
                class func resetStaticMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("typed throws method writes inout arguments back inside the catch")
    func typedThrowsInoutParameterWritesBack() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Parser {
                func parse(_ buffer: inout [UInt8]) throws(ParseError) -> String
            }
            """,
            expandedSource: """
            protocol Parser {
                func parse(_ buffer: inout [UInt8]) throws(ParseError) -> String
            }

            #if DEBUG
            class ParserMock: Parser {
                private(set) var parseCallCount: Int = 0
                private(set) var parseCallArguments: [[UInt8]] = []
                var parseHandler: (([UInt8]) throws -> (returnValue: String, inoutArgs: [UInt8]))? = nil
                func parse(_ buffer: inout [UInt8]) throws(ParseError) -> String {
                    parseCallCount += 1
                    parseCallArguments.append(buffer)
                    guard let _handler = parseHandler else {
                        fatalError("\\(Self.self).parseHandler is not set")
                    }
                    do {
                        let _result = try _handler(buffer)
                        buffer = _result.inoutArgs
                        return _result.returnValue
                    } catch {
                        throw error as! ParseError
                    }
                }
                func resetMock() {
                    parseCallCount = 0
                    parseCallArguments = []
                    parseHandler = nil
                }
                class func resetStaticMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Sendable typed throws method re-throws from behind the lock")
    func sendableTypedThrowsMethodReThrowsFromBehindLock() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Store: Sendable {
                func value() throws(StoreError) -> Int
            }
            """,
            expandedSource: """
            protocol Store: Sendable {
                func value() throws(StoreError) -> Int
            }

            #if DEBUG
            class StoreMock: Store, @unchecked Sendable {
                private struct Storage {
                    var valueCallCount: Int = 0
                    var valueHandler: (@Sendable () throws -> Int)? = nil
                }
                private let _storage = MockableLock<Storage>(Storage())
                var valueCallCount: Int {
                    _storage.withLock {
                        $0.valueCallCount
                    }
                }
                @available(*, deprecated, message: "value records no arguments; use valueCallCount instead.")
                var valueCallArguments: [()] {
                    Array(repeating: (), count: valueCallCount)
                }
                var valueHandler: (@Sendable () throws -> Int)? {
                    get {
                        _storage.withLock {
                            $0.valueHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.valueHandler = newValue
                        }
                    }
                }
                func value() throws(StoreError) -> Int {
                    let _handler = _storage.withLock { storage -> (@Sendable () throws -> Int)? in
                        storage.valueCallCount += 1
                        return storage.valueHandler
                    }
                    guard let _handler else {
                        fatalError("\\(Self.self).valueHandler is not set")
                    }
                    do {
                        return try _handler()
                    } catch {
                        throw error as! StoreError
                    }
                }
                func resetMock() {
                    _storage.withLock { storage in
                        storage.valueCallCount = 0
                        storage.valueHandler = nil
                    }
                }
                class func resetStaticMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("throws(Never) method is mocked with a non-throwing handler")
    func neverThrowsMethodUsesNonThrowingHandler() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Loader {
                func load(id: Int) throws(Never) -> String
            }
            """,
            expandedSource: """
            protocol Loader {
                func load(id: Int) throws(Never) -> String
            }

            #if DEBUG
            class LoaderMock: Loader {
                private(set) var loadCallCount: Int = 0
                private(set) var loadCallArguments: [Int] = []
                var loadHandler: ((Int) -> String)? = nil
                func load(id: Int) throws(Never) -> String {
                    loadCallCount += 1
                    loadCallArguments.append(id)
                    guard let _handler = loadHandler else {
                        fatalError("\\(Self.self).loadHandler is not set")
                    }
                    return _handler(id)
                }
                func resetMock() {
                    loadCallCount = 0
                    loadCallArguments = []
                    loadHandler = nil
                }
                class func resetStaticMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("throws(Never) async method awaits the handler without try")
    func neverThrowsAsyncMethodAwaitsHandler() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Fetcher {
                func fetch() async throws(Never) -> Data
            }
            """,
            expandedSource: """
            protocol Fetcher {
                func fetch() async throws(Never) -> Data
            }

            #if DEBUG
            class FetcherMock: Fetcher {
                private(set) var fetchCallCount: Int = 0
                @available(*, deprecated, message: "fetch records no arguments; use fetchCallCount instead.")
                var fetchCallArguments: [()] {
                    Array(repeating: (), count: fetchCallCount)
                }
                var fetchHandler: (() async -> Data)? = nil
                func fetch() async throws(Never) -> Data {
                    fetchCallCount += 1
                    guard let _handler = fetchHandler else {
                        fatalError("\\(Self.self).fetchHandler is not set")
                    }
                    return await _handler()
                }
                func resetMock() {
                    fetchCallCount = 0
                    fetchHandler = nil
                }
                class func resetStaticMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("throws(Never) method returning Void calls the handler without try")
    func neverThrowsVoidMethodCallsHandler() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Pinger {
                func ping() throws(Never)
            }
            """,
            expandedSource: """
            protocol Pinger {
                func ping() throws(Never)
            }

            #if DEBUG
            class PingerMock: Pinger {
                private(set) var pingCallCount: Int = 0
                @available(*, deprecated, message: "ping records no arguments; use pingCallCount instead.")
                var pingCallArguments: [()] {
                    Array(repeating: (), count: pingCallCount)
                }
                var pingHandler: (() -> Void)? = nil
                func ping() throws(Never) {
                    pingCallCount += 1
                    if let _handler = pingHandler {
                        _handler()
                    }
                }
                func resetMock() {
                    pingCallCount = 0
                    pingHandler = nil
                }
                class func resetStaticMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("throws(any Error) method is mocked like untyped throws")
    func anyErrorThrowsMethodIsMockedLikeUntypedThrows() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Loader {
                func load(id: Int) throws(any Error) -> String
            }
            """,
            expandedSource: """
            protocol Loader {
                func load(id: Int) throws(any Error) -> String
            }

            #if DEBUG
            class LoaderMock: Loader {
                private(set) var loadCallCount: Int = 0
                private(set) var loadCallArguments: [Int] = []
                var loadHandler: ((Int) throws -> String)? = nil
                func load(id: Int) throws(any Error) -> String {
                    loadCallCount += 1
                    loadCallArguments.append(id)
                    guard let _handler = loadHandler else {
                        fatalError("\\(Self.self).loadHandler is not set")
                    }
                    return try _handler(id)
                }
                func resetMock() {
                    loadCallCount = 0
                    loadCallArguments = []
                    loadHandler = nil
                }
                class func resetStaticMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("throws(Error) method is mocked like untyped throws")
    func bareErrorThrowsMethodIsMockedLikeUntypedThrows() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Loader {
                func load(id: Int) throws(Error) -> String
            }
            """,
            expandedSource: """
            protocol Loader {
                func load(id: Int) throws(Error) -> String
            }

            #if DEBUG
            class LoaderMock: Loader {
                private(set) var loadCallCount: Int = 0
                private(set) var loadCallArguments: [Int] = []
                var loadHandler: ((Int) throws -> String)? = nil
                func load(id: Int) throws(Error) -> String {
                    loadCallCount += 1
                    loadCallArguments.append(id)
                    guard let _handler = loadHandler else {
                        fatalError("\\(Self.self).loadHandler is not set")
                    }
                    return try _handler(id)
                }
                func resetMock() {
                    loadCallCount = 0
                    loadCallArguments = []
                    loadHandler = nil
                }
                class func resetStaticMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("throws(Never) property is mocked with a non-throwing handler")
    func neverThrowsPropertyUsesNonThrowingHandler() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol ConfigProvider {
                var setting: Int { get throws(Never) }
            }
            """,
            expandedSource: """
            protocol ConfigProvider {
                var setting: Int { get throws(Never) }
            }

            #if DEBUG
            class ConfigProviderMock: ConfigProvider {
                private(set) var settingCallCount: Int = 0
                var settingHandler: (() -> Int)? = nil
                var setting: Int {
                    get throws(Never) {
                        settingCallCount += 1
                        guard let _handler = settingHandler else {
                            fatalError("\\(Self.self).settingHandler is not set")
                        }
                        return _handler()
                    }
                }
                func resetMock() {
                    settingCallCount = 0
                    settingHandler = nil
                }
                class func resetStaticMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("typed throws property re-throws the typed error")
    func typedThrowsPropertyReThrowsTypedError() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol ConfigProvider {
                var setting: Int { get throws(ConfigError) }
            }
            """,
            expandedSource: """
            protocol ConfigProvider {
                var setting: Int { get throws(ConfigError) }
            }

            #if DEBUG
            class ConfigProviderMock: ConfigProvider {
                private(set) var settingCallCount: Int = 0
                var settingHandler: (() throws -> Int)? = nil
                var setting: Int {
                    get throws(ConfigError) {
                        settingCallCount += 1
                        guard let _handler = settingHandler else {
                            fatalError("\\(Self.self).settingHandler is not set")
                        }
                        do {
                            return try _handler()
                        } catch {
                            throw error as! ConfigError
                        }
                    }
                }
                func resetMock() {
                    settingCallCount = 0
                    settingHandler = nil
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
