import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import MockableMacros

@Suite("Basic Macro Tests")
struct BasicMacroTests {
    private let testMacros: [String: Macro.Type] = [
        "Mockable": MockableMacro.self
    ]

    @Test("Simple protocol with single method")
    func simpleProtocolWithMethod() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol UserService {
                func fetchUser(id: Int) -> String
            }
            """,
            expandedSource: """
            protocol UserService {
                func fetchUser(id: Int) -> String
            }

            #if DEBUG
            class UserServiceMock: UserService {
                var fetchUserCallCount: Int = 0
                var fetchUserCallArgs: [Int] = []
                var fetchUserHandler: (@Sendable (Int) -> String)? = nil
                func fetchUser(id: Int) -> String {
                    fetchUserCallCount += 1
                    fetchUserCallArgs.append(id)
                    guard let _handler = fetchUserHandler else {
                        fatalError("\\(Self.self).fetchUserHandler is not set")
                    }
                    return _handler(id)
                }
                func resetMock() {
                    fetchUserCallCount = 0
                    fetchUserCallArgs = []
                    fetchUserHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with async throws method")
    func asyncThrowsMethod() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol DataService {
                func loadData(from url: String) async throws -> Data
            }
            """,
            expandedSource: """
            protocol DataService {
                func loadData(from url: String) async throws -> Data
            }

            #if DEBUG
            class DataServiceMock: DataService {
                var loadDataCallCount: Int = 0
                var loadDataCallArgs: [String] = []
                var loadDataHandler: (@Sendable (String) async throws -> Data)? = nil
                func loadData(from url: String) async throws -> Data {
                    loadDataCallCount += 1
                    loadDataCallArgs.append(url)
                    guard let _handler = loadDataHandler else {
                        fatalError("\\(Self.self).loadDataHandler is not set")
                    }
                    return try await _handler(url)
                }
                func resetMock() {
                    loadDataCallCount = 0
                    loadDataCallArgs = []
                    loadDataHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with multiple parameters")
    func multipleParameters() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Calculator {
                func add(a: Int, b: Int) -> Int
            }
            """,
            expandedSource: """
            protocol Calculator {
                func add(a: Int, b: Int) -> Int
            }

            #if DEBUG
            class CalculatorMock: Calculator {
                var addCallCount: Int = 0
                var addCallArgs: [(a: Int, b: Int)] = []
                var addHandler: (@Sendable (Int, Int) -> Int)? = nil
                func add(a: Int, b: Int) -> Int {
                    addCallCount += 1
                    addCallArgs.append((a: a, b: b))
                    guard let _handler = addHandler else {
                        fatalError("\\(Self.self).addHandler is not set")
                    }
                    return _handler(a, b)
                }
                func resetMock() {
                    addCallCount = 0
                    addCallArgs = []
                    addHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with void method")
    func voidMethod() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Logger {
                func log(message: String)
            }
            """,
            expandedSource: """
            protocol Logger {
                func log(message: String)
            }

            #if DEBUG
            class LoggerMock: Logger {
                var logCallCount: Int = 0
                var logCallArgs: [String] = []
                var logHandler: (@Sendable (String) -> Void)? = nil
                func log(message: String) {
                    logCallCount += 1
                    logCallArgs.append(message)
                    if let _handler = logHandler {
                        _handler(message)
                    }
                }
                func resetMock() {
                    logCallCount = 0
                    logCallArgs = []
                    logHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with variadic parameter")
    func variadicParameterMethod() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Logger {
                func log(_ messages: String...)
            }
            """,
            expandedSource: """
            protocol Logger {
                func log(_ messages: String...)
            }

            #if DEBUG
            class LoggerMock: Logger {
                var logCallCount: Int = 0
                var logCallArgs: [[String]] = []
                var logHandler: (@Sendable ([String]) -> Void)? = nil
                func log(_ messages: String...) {
                    logCallCount += 1
                    logCallArgs.append(messages)
                    if let _handler = logHandler {
                        _handler(messages)
                    }
                }
                func resetMock() {
                    logCallCount = 0
                    logCallArgs = []
                    logHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with get-only property")
    func getOnlyProperty() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol UserProvider {
                var currentUser: String { get }
            }
            """,
            expandedSource: """
            protocol UserProvider {
                var currentUser: String { get }
            }

            #if DEBUG
            class UserProviderMock: UserProvider {
                var _currentUser: String? = nil
                var currentUser: String {
                    _currentUser!
                }
                func resetMock() {
                    _currentUser = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with get-set property")
    func getSetProperty() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Settings {
                var theme: String { get set }
            }
            """,
            expandedSource: """
            protocol Settings {
                var theme: String { get set }
            }

            #if DEBUG
            class SettingsMock: Settings {
                var _theme: String? = nil
                var theme: String {
                    get {
                        _theme!
                    }
                    set {
                        _theme = newValue
                    }
                }
                func resetMock() {
                    _theme = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with optional property")
    func optionalProperty() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Cache {
                var lastValue: String? { get set }
            }
            """,
            expandedSource: """
            protocol Cache {
                var lastValue: String? { get set }
            }

            #if DEBUG
            class CacheMock: Cache {
                var lastValue: String? = nil
                func resetMock() {
                    lastValue = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with static members")
    func staticMembers() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol SharedState {
                static func makeValue(prefix: String) -> String
                static var cachedToken: String { get }
                static var cachedCount: Int? { get set }
            }
            """,
            expandedSource: """
            protocol SharedState {
                static func makeValue(prefix: String) -> String
                static var cachedToken: String { get }
                static var cachedCount: Int? { get set }
            }

            #if DEBUG
            class SharedStateMock: SharedState {
                private struct StaticStorage {
                    var makeValueCallCount: Int = 0
                    var makeValueCallArgs: [String] = []
                    var makeValueHandler: (@Sendable (String) -> String)? = nil
                    var _cachedToken: String? = nil
                    var _cachedCount: Int? = nil
                }
                private static let _staticStorage = MockableLock<StaticStorage>(StaticStorage())
                static var makeValueCallCount: Int {
                    get {
                        _staticStorage.withLock {
                            $0.makeValueCallCount
                        }
                    }
                    set {
                        _staticStorage.withLock {
                            $0.makeValueCallCount = newValue
                        }
                    }
                }
                static var makeValueCallArgs: [String] {
                    get {
                        _staticStorage.withLock {
                            $0.makeValueCallArgs
                        }
                    }
                    set {
                        _staticStorage.withLock {
                            $0.makeValueCallArgs = newValue
                        }
                    }
                }
                static var makeValueHandler: (@Sendable (String) -> String)? {
                    get {
                        _staticStorage.withLock {
                            $0.makeValueHandler
                        }
                    }
                    set {
                        _staticStorage.withLock {
                            $0.makeValueHandler = newValue
                        }
                    }
                }
                static func makeValue(prefix: String) -> String {
                    let _handler = _staticStorage.withLock { storage -> (@Sendable (String) -> String)? in
                        storage.makeValueCallCount += 1
                        storage.makeValueCallArgs.append(prefix)
                        return storage.makeValueHandler
                    }
                    guard let _handler else {
                        fatalError("\\(Self.self).makeValueHandler is not set")
                    }
                    return _handler(prefix)
                }
                static var _cachedToken: String? {
                    get {
                        _staticStorage.withLock {
                            $0._cachedToken
                        }
                    }
                    set {
                        _staticStorage.withLock {
                            $0._cachedToken = newValue
                        }
                    }
                }
                static var cachedToken: String {
                    _staticStorage.withLock {
                        $0._cachedToken!
                    }
                }
                static var _cachedCount: Int? {
                    get {
                        _staticStorage.withLock {
                            $0._cachedCount
                        }
                    }
                    set {
                        _staticStorage.withLock {
                            $0._cachedCount = newValue
                        }
                    }
                }
                static var cachedCount: Int? {
                    get {
                        _staticStorage.withLock {
                            $0._cachedCount
                        }
                    }
                    set {
                        _staticStorage.withLock {
                            $0._cachedCount = newValue
                        }
                    }
                }
                func resetMock() {
                    Self.makeValueCallCount = 0
                    Self.makeValueCallArgs = []
                    Self.makeValueHandler = nil
                    Self._cachedToken = nil
                    Self.cachedCount = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Non-protocol declaration should fail")
    func nonProtocolFails() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            class MyClass {}
            """,
            expandedSource: """
            class MyClass {}
            """,
            diagnostics: [
                DiagnosticSpec(message: "@Mockable can only be applied to protocols", line: 1, column: 1)
            ],
            macros: testMacros
        )
    }

    @Test("Unsupported protocol members should produce diagnostics")
    func unsupportedMembersProduceDiagnostics() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol UnsupportedRequirements {
                init(token: String)
            }
            """,
            expandedSource: """
            protocol UnsupportedRequirements {
                init(token: String)
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "Unsupported protocol member: init(token: String)", line: 3, column: 5)
            ],
            macros: testMacros
        )
    }

    @Test("Invalid macro arguments should produce diagnostics")
    func invalidMacroArgumentsProduceDiagnostics() {
        assertMacroExpansionForTesting(
            """
            @Mockable(debug: true)
            protocol CacheService {
                func clear()
            }
            """,
            expandedSource: """
            protocol CacheService {
                func clear()
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "Invalid @Mockable argument: unexpected argument label 'debug'; @Mockable does not accept arguments", line: 1, column: 11)
            ],
            macros: testMacros
        )
    }

    @Test("Protocol with @escaping closure parameter")
    func escapingClosureParameter() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol EventHandler {
                func subscribe(handler: @escaping (String) -> Void)
            }
            """,
            expandedSource: """
            protocol EventHandler {
                func subscribe(handler: @escaping (String) -> Void)
            }

            #if DEBUG
            class EventHandlerMock: EventHandler {
                var subscribeCallCount: Int = 0
                var subscribeCallArgs: [(String) -> Void] = []
                var subscribeHandler: (@Sendable ((String) -> Void) -> Void)? = nil
                func subscribe(handler: @escaping (String) -> Void) {
                    subscribeCallCount += 1
                    subscribeCallArgs.append(handler)
                    if let _handler = subscribeHandler {
                        _handler(handler)
                    }
                }
                func resetMock() {
                    subscribeCallCount = 0
                    subscribeCallArgs = []
                    subscribeHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with @escaping @Sendable closure parameter")
    func escapingSendableClosureParameter() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol EventHandler {
                func subscribe(handler: @escaping @Sendable (String) -> Void)
            }
            """,
            expandedSource: """
            protocol EventHandler {
                func subscribe(handler: @escaping @Sendable (String) -> Void)
            }

            #if DEBUG
            class EventHandlerMock: EventHandler {
                var subscribeCallCount: Int = 0
                var subscribeCallArgs: [@Sendable (String) -> Void] = []
                var subscribeHandler: (@Sendable (@Sendable (String) -> Void) -> Void)? = nil
                func subscribe(handler: @escaping @Sendable (String) -> Void) {
                    subscribeCallCount += 1
                    subscribeCallArgs.append(handler)
                    if let _handler = subscribeHandler {
                        _handler(handler)
                    }
                }
                func resetMock() {
                    subscribeCallCount = 0
                    subscribeCallArgs = []
                    subscribeHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with parenthesized @escaping closure parameter")
    func parenthesizedEscapingClosureParameter() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol CompletionHandler {
                func doSomething(completion: (@escaping (Error?) -> Void))
            }
            """,
            expandedSource: """
            protocol CompletionHandler {
                func doSomething(completion: (@escaping (Error?) -> Void))
            }

            #if DEBUG
            class CompletionHandlerMock: CompletionHandler {
                var doSomethingCallCount: Int = 0
                var doSomethingCallArgs: [(Error?) -> Void] = []
                var doSomethingHandler: (@Sendable ((Error?) -> Void) -> Void)? = nil
                func doSomething(completion: (@escaping (Error?) -> Void)) {
                    doSomethingCallCount += 1
                    doSomethingCallArgs.append(completion)
                    if let _handler = doSomethingHandler {
                        _handler(completion)
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

    @Test("Protocol with parenthesized @escaping @Sendable closure parameter")
    func parenthesizedEscapingSendableClosureParameter() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol CompletionHandler {
                func doSomething(completion: (@escaping @Sendable (Error?) -> Void))
            }
            """,
            expandedSource: """
            protocol CompletionHandler {
                func doSomething(completion: (@escaping @Sendable (Error?) -> Void))
            }

            #if DEBUG
            class CompletionHandlerMock: CompletionHandler {
                var doSomethingCallCount: Int = 0
                var doSomethingCallArgs: [@Sendable (Error?) -> Void] = []
                var doSomethingHandler: (@Sendable (@Sendable (Error?) -> Void) -> Void)? = nil
                func doSomething(completion: (@escaping @Sendable (Error?) -> Void)) {
                    doSomethingCallCount += 1
                    doSomethingCallArgs.append(completion)
                    if let _handler = doSomethingHandler {
                        _handler(completion)
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

    @Test("Method with optional return returns nil when handler is unset")
    func optionalReturnDefaultsToNil() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Repository {
                func fetch() -> String?
            }
            """,
            expandedSource: """
            protocol Repository {
                func fetch() -> String?
            }

            #if DEBUG
            class RepositoryMock: Repository {
                var fetchCallCount: Int = 0
                var fetchCallArgs: [()] = []
                var fetchHandler: (@Sendable () -> String?)? = nil
                func fetch() -> String? {
                    fetchCallCount += 1
                    fetchCallArgs.append(())
                    guard let _handler = fetchHandler else {
                        return nil
                    }
                    return _handler()
                }
                func resetMock() {
                    fetchCallCount = 0
                    fetchCallArgs = []
                    fetchHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Method with array return returns empty array when handler is unset")
    func arrayReturnDefaultsToEmptyArray() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Repository {
                func items() -> [String]
            }
            """,
            expandedSource: """
            protocol Repository {
                func items() -> [String]
            }

            #if DEBUG
            class RepositoryMock: Repository {
                var itemsCallCount: Int = 0
                var itemsCallArgs: [()] = []
                var itemsHandler: (@Sendable () -> [String])? = nil
                func items() -> [String] {
                    itemsCallCount += 1
                    itemsCallArgs.append(())
                    guard let _handler = itemsHandler else {
                        return []
                    }
                    return _handler()
                }
                func resetMock() {
                    itemsCallCount = 0
                    itemsCallArgs = []
                    itemsHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Method with set return returns empty collection when handler is unset")
    func setReturnDefaultsToEmptyCollection() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Repository {
                func tags() -> Set<String>
            }
            """,
            expandedSource: """
            protocol Repository {
                func tags() -> Set<String>
            }

            #if DEBUG
            class RepositoryMock: Repository {
                var tagsCallCount: Int = 0
                var tagsCallArgs: [()] = []
                var tagsHandler: (@Sendable () -> Set<String>)? = nil
                func tags() -> Set<String> {
                    tagsCallCount += 1
                    tagsCallArgs.append(())
                    guard let _handler = tagsHandler else {
                        return []
                    }
                    return _handler()
                }
                func resetMock() {
                    tagsCallCount = 0
                    tagsCallArgs = []
                    tagsHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Method with dictionary return returns empty dictionary when handler is unset")
    func dictionaryReturnDefaultsToEmptyDictionary() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Repository {
                func mapping() -> [String: Int]
            }
            """,
            expandedSource: """
            protocol Repository {
                func mapping() -> [String: Int]
            }

            #if DEBUG
            class RepositoryMock: Repository {
                var mappingCallCount: Int = 0
                var mappingCallArgs: [()] = []
                var mappingHandler: (@Sendable () -> [String: Int])? = nil
                func mapping() -> [String: Int] {
                    mappingCallCount += 1
                    mappingCallArgs.append(())
                    guard let _handler = mappingHandler else {
                        return [:]
                    }
                    return _handler()
                }
                func resetMock() {
                    mappingCallCount = 0
                    mappingCallArgs = []
                    mappingHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Long-form Optional, Array and Dictionary returns use empty defaults")
    func longFormCollectionsDefaultToEmpty() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Repository {
                func optionalValue() -> Optional<String>
                func arrayValue() -> Array<String>
                func dictionaryValue() -> Dictionary<String, Int>
            }
            """,
            expandedSource: """
            protocol Repository {
                func optionalValue() -> Optional<String>
                func arrayValue() -> Array<String>
                func dictionaryValue() -> Dictionary<String, Int>
            }

            #if DEBUG
            class RepositoryMock: Repository {
                var optionalValueCallCount: Int = 0
                var optionalValueCallArgs: [()] = []
                var optionalValueHandler: (@Sendable () -> Optional<String>)? = nil
                func optionalValue() -> Optional<String> {
                    optionalValueCallCount += 1
                    optionalValueCallArgs.append(())
                    guard let _handler = optionalValueHandler else {
                        return nil
                    }
                    return _handler()
                }
                var arrayValueCallCount: Int = 0
                var arrayValueCallArgs: [()] = []
                var arrayValueHandler: (@Sendable () -> Array<String>)? = nil
                func arrayValue() -> Array<String> {
                    arrayValueCallCount += 1
                    arrayValueCallArgs.append(())
                    guard let _handler = arrayValueHandler else {
                        return []
                    }
                    return _handler()
                }
                var dictionaryValueCallCount: Int = 0
                var dictionaryValueCallArgs: [()] = []
                var dictionaryValueHandler: (@Sendable () -> Dictionary<String, Int>)? = nil
                func dictionaryValue() -> Dictionary<String, Int> {
                    dictionaryValueCallCount += 1
                    dictionaryValueCallArgs.append(())
                    guard let _handler = dictionaryValueHandler else {
                        return [:]
                    }
                    return _handler()
                }
                func resetMock() {
                    optionalValueCallCount = 0
                    optionalValueCallArgs = []
                    optionalValueHandler = nil
                    arrayValueCallCount = 0
                    arrayValueCallArgs = []
                    arrayValueHandler = nil
                    dictionaryValueCallCount = 0
                    dictionaryValueCallArgs = []
                    dictionaryValueHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Module-qualified Swift.Optional, Swift.Array, Swift.Set and Swift.Dictionary returns use empty defaults")
    func moduleQualifiedCollectionsDefaultToEmpty() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Repository {
                func optionalValue() -> Swift.Optional<String>
                func arrayValue() -> Swift.Array<String>
                func setValue() -> Swift.Set<String>
                func dictionaryValue() -> Swift.Dictionary<String, Int>
            }
            """,
            expandedSource: """
            protocol Repository {
                func optionalValue() -> Swift.Optional<String>
                func arrayValue() -> Swift.Array<String>
                func setValue() -> Swift.Set<String>
                func dictionaryValue() -> Swift.Dictionary<String, Int>
            }

            #if DEBUG
            class RepositoryMock: Repository {
                var optionalValueCallCount: Int = 0
                var optionalValueCallArgs: [()] = []
                var optionalValueHandler: (@Sendable () -> Swift.Optional<String>)? = nil
                func optionalValue() -> Swift.Optional<String> {
                    optionalValueCallCount += 1
                    optionalValueCallArgs.append(())
                    guard let _handler = optionalValueHandler else {
                        return nil
                    }
                    return _handler()
                }
                var arrayValueCallCount: Int = 0
                var arrayValueCallArgs: [()] = []
                var arrayValueHandler: (@Sendable () -> Swift.Array<String>)? = nil
                func arrayValue() -> Swift.Array<String> {
                    arrayValueCallCount += 1
                    arrayValueCallArgs.append(())
                    guard let _handler = arrayValueHandler else {
                        return []
                    }
                    return _handler()
                }
                var setValueCallCount: Int = 0
                var setValueCallArgs: [()] = []
                var setValueHandler: (@Sendable () -> Swift.Set<String>)? = nil
                func setValue() -> Swift.Set<String> {
                    setValueCallCount += 1
                    setValueCallArgs.append(())
                    guard let _handler = setValueHandler else {
                        return []
                    }
                    return _handler()
                }
                var dictionaryValueCallCount: Int = 0
                var dictionaryValueCallArgs: [()] = []
                var dictionaryValueHandler: (@Sendable () -> Swift.Dictionary<String, Int>)? = nil
                func dictionaryValue() -> Swift.Dictionary<String, Int> {
                    dictionaryValueCallCount += 1
                    dictionaryValueCallArgs.append(())
                    guard let _handler = dictionaryValueHandler else {
                        return [:]
                    }
                    return _handler()
                }
                func resetMock() {
                    optionalValueCallCount = 0
                    optionalValueCallArgs = []
                    optionalValueHandler = nil
                    arrayValueCallCount = 0
                    arrayValueCallArgs = []
                    arrayValueHandler = nil
                    setValueCallCount = 0
                    setValueCallArgs = []
                    setValueHandler = nil
                    dictionaryValueCallCount = 0
                    dictionaryValueCallArgs = []
                    dictionaryValueHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Method with implicitly unwrapped optional return returns nil when handler is unset")
    func implicitlyUnwrappedOptionalReturnDefaultsToNil() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Repository {
                func fetch() -> String!
            }
            """,
            expandedSource: """
            protocol Repository {
                func fetch() -> String!
            }

            #if DEBUG
            class RepositoryMock: Repository {
                var fetchCallCount: Int = 0
                var fetchCallArgs: [()] = []
                var fetchHandler: (@Sendable () -> String?)? = nil
                func fetch() -> String! {
                    fetchCallCount += 1
                    fetchCallArgs.append(())
                    guard let _handler = fetchHandler else {
                        return nil
                    }
                    return _handler()
                }
                func resetMock() {
                    fetchCallCount = 0
                    fetchCallArgs = []
                    fetchHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Nested collection returns use the outermost type for the default")
    func nestedCollectionReturnsUseOutermostType() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Repository {
                func optionalArray() -> [String]?
                func arrayOfOptional() -> [String?]
            }
            """,
            expandedSource: """
            protocol Repository {
                func optionalArray() -> [String]?
                func arrayOfOptional() -> [String?]
            }

            #if DEBUG
            class RepositoryMock: Repository {
                var optionalArrayCallCount: Int = 0
                var optionalArrayCallArgs: [()] = []
                var optionalArrayHandler: (@Sendable () -> [String]?)? = nil
                func optionalArray() -> [String]? {
                    optionalArrayCallCount += 1
                    optionalArrayCallArgs.append(())
                    guard let _handler = optionalArrayHandler else {
                        return nil
                    }
                    return _handler()
                }
                var arrayOfOptionalCallCount: Int = 0
                var arrayOfOptionalCallArgs: [()] = []
                var arrayOfOptionalHandler: (@Sendable () -> [String?])? = nil
                func arrayOfOptional() -> [String?] {
                    arrayOfOptionalCallCount += 1
                    arrayOfOptionalCallArgs.append(())
                    guard let _handler = arrayOfOptionalHandler else {
                        return []
                    }
                    return _handler()
                }
                func resetMock() {
                    optionalArrayCallCount = 0
                    optionalArrayCallArgs = []
                    optionalArrayHandler = nil
                    arrayOfOptionalCallCount = 0
                    arrayOfOptionalCallArgs = []
                    arrayOfOptionalHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }
}
