import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import MockableMacros

/// Requirements whose parameter names the generated bodies cannot refer to as written:
/// a wildcard names nothing, a keyword needs escaping, and a name that matches one of
/// the mock's own locals or members would capture it.
@Suite("Parameter Name Macro Tests")
struct ParameterNameMacroTests {
    let testMacros: [String: Macro.Type] = [
        "Mockable": MockableMacro.self
    ]

    // MARK: - Names the body cannot spell

    @Test("A wildcard parameter gets a synthesized internal name")
    func wildcardParameter() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Service {
                func handle(_: Int) -> Int
            }
            """,
            expandedSource: """
            protocol Service {
                func handle(_: Int) -> Int
            }

            #if DEBUG
            class ServiceMock: Service {
                private(set) var handleCallCount: Int = 0
                private(set) var handleCallArguments: [Int] = []
                var handleHandler: ((Int) -> Int)? = nil
                func handle(_ param0: Int) -> Int {
                    handleCallCount += 1
                    handleCallArguments.append(param0)
                    guard let _handler = handleHandler else {
                        fatalError("\\(Self.self).handleHandler is not set")
                    }
                    return _handler(param0)
                }
                func resetMock() {
                    handleCallCount = 0
                    handleCallArguments = []
                    handleHandler = nil
                }
                class func resetStaticMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Several wildcard parameters are numbered by position")
    func severalWildcardParameters() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Service {
                func pair(_: Int, _: String)
            }
            """,
            expandedSource: """
            protocol Service {
                func pair(_: Int, _: String)
            }

            #if DEBUG
            class ServiceMock: Service {
                private(set) var pairCallCount: Int = 0
                private(set) var pairCallArguments: [(param0: Int, param1: String)] = []
                var pairHandler: ((Int, String) -> Void)? = nil
                func pair(_ param0: Int, _ param1: String) {
                    pairCallCount += 1
                    pairCallArguments.append((param0: param0, param1: param1))
                    if let _handler = pairHandler {
                        _handler(param0, param1)
                    }
                }
                func resetMock() {
                    pairCallCount = 0
                    pairCallArguments = []
                    pairHandler = nil
                }
                class func resetStaticMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("A synthesized name steps aside for a parameter that already has it")
    func synthesizedNameCollision() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Service {
                func take(_: Int, param0: String)
            }
            """,
            expandedSource: """
            protocol Service {
                func take(_: Int, param0: String)
            }

            #if DEBUG
            class ServiceMock: Service {
                private(set) var takeCallCount: Int = 0
                private(set) var takeCallArguments: [(param0_: Int, param0: String)] = []
                var takeHandler: ((Int, String) -> Void)? = nil
                func take(_ param0_: Int, param0: String) {
                    takeCallCount += 1
                    takeCallArguments.append((param0_: param0_, param0: param0))
                    if let _handler = takeHandler {
                        _handler(param0_, param0)
                    }
                }
                func resetMock() {
                    takeCallCount = 0
                    takeCallArguments = []
                    takeHandler = nil
                }
                class func resetStaticMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("A keyword parameter name is escaped, keeping the argument label")
    func keywordParameterName() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Service {
                func value(for: Int) -> Int
            }
            """,
            expandedSource: """
            protocol Service {
                func value(for: Int) -> Int
            }

            #if DEBUG
            class ServiceMock: Service {
                private(set) var valueCallCount: Int = 0
                private(set) var valueCallArguments: [Int] = []
                var valueHandler: ((Int) -> Int)? = nil
                func value(`for`: Int) -> Int {
                    valueCallCount += 1
                    valueCallArguments.append(`for`)
                    guard let _handler = valueHandler else {
                        fatalError("\\(Self.self).valueHandler is not set")
                    }
                    return _handler(`for`)
                }
                func resetMock() {
                    valueCallCount = 0
                    valueCallArguments = []
                    valueHandler = nil
                }
                class func resetStaticMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Escaped keyword names are labels as they stand and references escaped")
    func keywordParameterNamesInTuple() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Service {
                func log(for: Int, in: String)
            }
            """,
            expandedSource: """
            protocol Service {
                func log(for: Int, in: String)
            }

            #if DEBUG
            class ServiceMock: Service {
                private(set) var logCallCount: Int = 0
                private(set) var logCallArguments: [(for: Int, in: String)] = []
                var logHandler: ((Int, String) -> Void)? = nil
                func log(`for`: Int, `in`: String) {
                    logCallCount += 1
                    logCallArguments.append((for: `for`, in: `in`))
                    if let _handler = logHandler {
                        _handler(`for`, `in`)
                    }
                }
                func resetMock() {
                    logCallCount = 0
                    logCallArguments = []
                    logHandler = nil
                }
                class func resetStaticMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    // MARK: - Names that would capture the mock's own locals and members

    @Test("A parameter named after the lock closure's binding moves it aside")
    func parameterShadowingStorageBinding() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Service: Sendable {
                func save(storage: Int)
            }
            """,
            expandedSource: """
            protocol Service: Sendable {
                func save(storage: Int)
            }

            #if DEBUG
            class ServiceMock: Service, @unchecked Sendable {
                private struct Storage {
                    var saveCallCount: Int = 0
                    var saveCallArguments: [Int] = []
                    var saveHandler: (@Sendable (Int) -> Void)? = nil
                }
                private let _storage = MockableLock<Storage>(Storage())
                var saveCallCount: Int {
                    _storage.withLock {
                        $0.saveCallCount
                    }
                }
                var saveCallArguments: [Int] {
                    _storage.withLock {
                        $0.saveCallArguments
                    }
                }
                var saveHandler: (@Sendable (Int) -> Void)? {
                    get {
                        _storage.withLock {
                            $0.saveHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.saveHandler = newValue
                        }
                    }
                }
                func save(storage: Int) {
                    let _handler = _storage.withLock { storage_ -> (@Sendable (Int) -> Void)? in
                        storage_.saveCallCount += 1
                        storage_.saveCallArguments.append(storage)
                        return storage_.saveHandler
                    }
                    if let _handler {
                        _handler(storage)
                    }
                }
                func resetMock() {
                    _storage.withLock { storage in
                        storage.saveCallCount = 0
                        storage.saveCallArguments = []
                        storage.saveHandler = nil
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

    @Test("A parameter named after the handler binding moves it aside")
    func parameterShadowingHandlerBinding() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Service {
                func run(_handler: Int)
            }
            """,
            expandedSource: """
            protocol Service {
                func run(_handler: Int)
            }

            #if DEBUG
            class ServiceMock: Service {
                private(set) var runCallCount: Int = 0
                private(set) var runCallArguments: [Int] = []
                var runHandler: ((Int) -> Void)? = nil
                func run(_handler: Int) {
                    runCallCount += 1
                    runCallArguments.append(_handler)
                    if let _handler_ = runHandler {
                        _handler_(_handler)
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

    @Test("A parameter named after a tracking member is read through self")
    func parameterShadowingTrackingMember() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Service {
                func fetch(fetchCallCount: Int)
            }
            """,
            expandedSource: """
            protocol Service {
                func fetch(fetchCallCount: Int)
            }

            #if DEBUG
            class ServiceMock: Service {
                private(set) var fetchCallCount: Int = 0
                private(set) var fetchCallArguments: [Int] = []
                var fetchHandler: ((Int) -> Void)? = nil
                func fetch(fetchCallCount: Int) {
                    self.fetchCallCount += 1
                    self.fetchCallArguments.append(fetchCallCount)
                    if let _handler = self.fetchHandler {
                        _handler(fetchCallCount)
                    }
                }
                func resetMock() {
                    fetchCallCount = 0
                    fetchCallArguments = []
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

    @Test("A static requirement's parameter named after the storage is read through Self")
    func staticParameterShadowingStorage() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Service {
                static func store(_staticStorage: Int)
            }
            """,
            expandedSource: """
            protocol Service {
                static func store(_staticStorage: Int)
            }

            #if DEBUG
            class ServiceMock: Service {
                private struct StaticStorage {
                    var storeCallCount: Int = 0
                    var storeCallArguments: [Int] = []
                    var storeHandler: (@Sendable (Int) -> Void)? = nil
                }
                private static let _staticStorage = MockableLock<StaticStorage>(StaticStorage())
                static var storeCallCount: Int {
                    _staticStorage.withLock {
                        $0.storeCallCount
                    }
                }
                static var storeCallArguments: [Int] {
                    _staticStorage.withLock {
                        $0.storeCallArguments
                    }
                }
                static var storeHandler: (@Sendable (Int) -> Void)? {
                    get {
                        _staticStorage.withLock {
                            $0.storeHandler
                        }
                    }
                    set {
                        _staticStorage.withLock {
                            $0.storeHandler = newValue
                        }
                    }
                }
                static func store(_staticStorage: Int) {
                    let _handler = Self._staticStorage.withLock { storage -> (@Sendable (Int) -> Void)? in
                        storage.storeCallCount += 1
                        storage.storeCallArguments.append(_staticStorage)
                        return storage.storeHandler
                    }
                    if let _handler {
                        _handler(_staticStorage)
                    }
                }
                func resetMock() {
                }
                class func resetStaticMock() {
                    Self._staticStorage.withLock { storage in
                        storage.storeCallCount = 0
                        storage.storeCallArguments = []
                        storage.storeHandler = nil
                    }
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("A subscript index named newValue moves the setter's accessor parameter aside")
    func subscriptIndexNamedNewValue() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Service {
                subscript(newValue: Int) -> String { get set }
            }
            """,
            expandedSource: """
            protocol Service {
                subscript(newValue: Int) -> String { get set }
            }

            #if DEBUG
            class ServiceMock: Service {
                private(set) var subscriptIntCallCount: Int = 0
                private(set) var subscriptIntCallArguments: [Int] = []
                var subscriptIntHandler: ((Int) -> String )? = nil
                var subscriptIntSetHandler: ((Int, String ) -> Void)? = nil
                subscript(newValue: Int) -> String {
                    get {
                        subscriptIntCallCount += 1
                        subscriptIntCallArguments.append(newValue)
                        guard let _handler = subscriptIntHandler else {
                            fatalError("\\(Self.self).subscriptIntHandler is not set")
                        }
                        return _handler(newValue)
                    }
                    set(newValue_) {
                        if let _handler = subscriptIntSetHandler {
                            _handler(newValue, newValue_)
                        }
                    }
                }
                func resetMock() {
                    subscriptIntCallCount = 0
                    subscriptIntCallArguments = []
                    subscriptIntHandler = nil
                    subscriptIntSetHandler = nil
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

@Suite("Parameter Name Tests")
struct ParameterNameUnitTests {
    @Test("Plain identifiers can be referred to as they stand")
    func plainIdentifiersAreReferenceable() {
        for name in ["value", "param0", "storage", "_handler", "set", "get", "any", "async", "each"] {
            #expect(ParameterNaming.isBodyReferenceableName(name), "\(name) should be referenceable")
        }
    }

    @Test("Keywords, literals, and the wildcard need a different spelling")
    func keywordsAreNotReferenceable() {
        for name in ["for", "in", "repeat", "await", "nil", "true", "false", "_"] {
            #expect(!ParameterNaming.isBodyReferenceableName(name), "\(name) should not be referenceable")
        }
    }

    @Test("Names bound by the enclosing type need a different spelling")
    func contextuallyBoundNamesAreNotReferenceable() {
        for name in ["self", "Self", "super"] {
            #expect(!ParameterNaming.isBodyReferenceableName(name), "\(name) should not be referenceable")
        }
    }

    @Test("An already escaped name is referenceable as it stands")
    func escapedNameIsReferenceable() {
        #expect(ParameterNaming.isBodyReferenceableName("`repeat`"))
    }

    @Test("Normalizing a clause of ordinary parameters changes nothing")
    func normalizationIsANoOpForOrdinaryParameters() {
        let decl: DeclSyntax = "func f(_ a: Int, b: String, c d: Double)"
        let parameters = decl.as(FunctionDeclSyntax.self)!.signature.parameterClause.parameters
        let normalized = ParameterNaming.parametersWithReferenceableNames(parameters)
        #expect(normalized.description == parameters.description)
    }

    @Test("Normalization is idempotent")
    func normalizationIsIdempotent() {
        let decl: DeclSyntax = "func f(_: Int, for: String)"
        let parameters = decl.as(FunctionDeclSyntax.self)!.signature.parameterClause.parameters
        let once = ParameterNaming.parametersWithReferenceableNames(parameters)
        let twice = ParameterNaming.parametersWithReferenceableNames(once)
        #expect(once.description == twice.description)
    }
}
