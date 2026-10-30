import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import MockableMacros

@Suite("Initializer Macro Tests")
struct InitializerMacroTests {
    private let testMacros: [String: Macro.Type] = [
        "Mockable": MockableMacro.self
    ]

    @Test("Protocol with a single init requirement generates a recording required init")
    func singleInitializer() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Repository {
                init(id: String)
                func fetch() -> Int
            }
            """,
            expandedSource: """
            protocol Repository {
                init(id: String)
                func fetch() -> Int
            }

            #if DEBUG
            class RepositoryMock: Repository {
                private(set) var initCallCount: Int = 0
                private(set) var initCallArguments: [String] = []
                required init(id: String) {
                    initCallCount += 1
                    initCallArguments.append(id)
                }
                private(set) var fetchCallCount: Int = 0
                @available(*, deprecated, message: "fetch records no arguments; use fetchCallCount instead.")
                var fetchCallArguments: [()] {
                    Array(repeating: (), count: fetchCallCount)
                }
                var fetchHandler: (() -> Int)? = nil
                func fetch() -> Int {
                    fetchCallCount += 1
                    guard let _handler = fetchHandler else {
                        fatalError("\\(Self.self).fetchHandler is not set")
                    }
                    return _handler()
                }
                func resetMock() {
                    initCallCount = 0
                    initCallArguments = []
                    fetchCallCount = 0
                    fetchHandler = nil
                }
                class func resetMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Parameterless init requirement")
    func parameterlessInitializer() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Service {
                init()
            }
            """,
            expandedSource: """
            protocol Service {
                init()
            }

            #if DEBUG
            class ServiceMock: Service {
                private(set) var initCallCount: Int = 0
                @available(*, deprecated, message: "init records no arguments; use initCallCount instead.")
                var initCallArguments: [()] {
                    Array(repeating: (), count: initCallCount)
                }
                required init() {
                    initCallCount += 1
                }
                func resetMock() {
                    initCallCount = 0
                }
                class func resetMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Init requirement with multiple parameters records a labeled tuple")
    func multipleParameterInitializer() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Endpoint {
                init(host: String, port: Int)
            }
            """,
            expandedSource: """
            protocol Endpoint {
                init(host: String, port: Int)
            }

            #if DEBUG
            class EndpointMock: Endpoint {
                private(set) var initCallCount: Int = 0
                private(set) var initCallArguments: [(host: String, port: Int)] = []
                required init(host: String, port: Int) {
                    initCallCount += 1
                    initCallArguments.append((host: host, port: port))
                }
                func resetMock() {
                    initCallCount = 0
                    initCallArguments = []
                }
                class func resetMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Overloaded init requirements are disambiguated by parameter types")
    func overloadedInitializers() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Connection {
                init(host: String)
                init(host: String, port: Int)
            }
            """,
            expandedSource: """
            protocol Connection {
                init(host: String)
                init(host: String, port: Int)
            }

            #if DEBUG
            class ConnectionMock: Connection {
                private(set) var initHostCallCount: Int = 0
                private(set) var initHostCallArguments: [String] = []
                required init(host: String) {
                    initHostCallCount += 1
                    initHostCallArguments.append(host)
                }
                private(set) var initHostPortCallCount: Int = 0
                private(set) var initHostPortCallArguments: [(host: String, port: Int)] = []
                required init(host: String, port: Int) {
                    initHostPortCallCount += 1
                    initHostPortCallArguments.append((host: host, port: port))
                }
                func resetMock() {
                    initHostCallCount = 0
                    initHostCallArguments = []
                    initHostPortCallCount = 0
                    initHostPortCallArguments = []
                }
                class func resetMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Throwing init requirement keeps the throws effect")
    func throwingInitializer() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Loader {
                init(path: String) throws
            }
            """,
            expandedSource: """
            protocol Loader {
                init(path: String) throws
            }

            #if DEBUG
            class LoaderMock: Loader {
                private(set) var initCallCount: Int = 0
                private(set) var initCallArguments: [String] = []
                required init(path: String) throws {
                    initCallCount += 1
                    initCallArguments.append(path)
                }
                func resetMock() {
                    initCallCount = 0
                    initCallArguments = []
                }
                class func resetMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Failable init requirement keeps the optional marker")
    func failableInitializer() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Parser {
                init?(raw: String)
            }
            """,
            expandedSource: """
            protocol Parser {
                init?(raw: String)
            }

            #if DEBUG
            class ParserMock: Parser {
                private(set) var initCallCount: Int = 0
                private(set) var initCallArguments: [String] = []
                required init?(raw: String) {
                    initCallCount += 1
                    initCallArguments.append(raw)
                }
                func resetMock() {
                    initCallCount = 0
                    initCallArguments = []
                }
                class func resetMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Public protocol generates a public required init and omits the synthesized init()")
    func publicProtocolInitializer() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            public protocol Client {
                init(token: String)
            }
            """,
            expandedSource: """
            public protocol Client {
                init(token: String)
            }

            #if DEBUG
            open class ClientMock: Client {
                public private(set) var initCallCount: Int = 0
                public private(set) var initCallArguments: [String] = []
                public required init(token: String) {
                    initCallCount += 1
                    initCallArguments.append(token)
                }
                open func resetMock() {
                    initCallCount = 0
                    initCallArguments = []
                }
                open class func resetMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Init requirement is generated in source order alongside other members")
    func initializerWithProperty() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Widget {
                var name: String { get }
                init(name: String)
            }
            """,
            expandedSource: """
            protocol Widget {
                var name: String { get }
                init(name: String)
            }

            #if DEBUG
            class WidgetMock: Widget {
                private var _name: String? = nil
                var name: String {
                    get {
                        _name!
                    }
                    set {
                        _name = newValue
                    }
                }
                private(set) var initCallCount: Int = 0
                private(set) var initCallArguments: [String] = []
                required init(name: String) {
                    initCallCount += 1
                    initCallArguments.append(name)
                }
                func resetMock() {
                    _name = nil
                    initCallCount = 0
                    initCallArguments = []
                }
                class func resetMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("@MainActor protocol supports init requirements")
    func mainActorInitializer() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            @MainActor
            protocol Presenter {
                init(title: String)
            }
            """,
            expandedSource: """
            @MainActor
            protocol Presenter {
                init(title: String)
            }

            #if DEBUG
            @MainActor class PresenterMock: Presenter {
                private(set) var initCallCount: Int = 0
                private(set) var initCallArguments: [String] = []
                required init(title: String) {
                    initCallCount += 1
                    initCallArguments.append(title)
                }
                func resetMock() {
                    initCallCount = 0
                    initCallArguments = []
                }
                class func resetMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Sendable protocol records the init call behind the lock")
    func sendableInitializer() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol SendableService: Sendable {
                init(id: String)
            }
            """,
            expandedSource: """
            protocol SendableService: Sendable {
                init(id: String)
            }

            #if DEBUG
            class SendableServiceMock: SendableService, @unchecked Sendable {
                private struct Storage {
                    var initCallCount: Int = 0
                    var initCallArguments: [String] = []
                }
                private let _storage = MockableLock<Storage>(Storage())
                var initCallCount: Int {
                    _storage.withLock {
                        $0.initCallCount
                    }
                }
                var initCallArguments: [String] {
                    _storage.withLock {
                        $0.initCallArguments
                    }
                }
                required init(id: String) {
                    _storage.withLock { storage in
                        storage.initCallCount += 1
                        storage.initCallArguments.append(id)
                    }
                }
                func resetMock() {
                    _storage.withLock { storage in
                        storage.initCallCount = 0
                        storage.initCallArguments = []
                    }
                }
                class func resetMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Actor protocol records the init call without required")
    func actorInitializer() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol ActorService: Actor {
                init(id: String)
            }
            """,
            expandedSource: """
            protocol ActorService: Actor {
                init(id: String)
            }

            #if DEBUG
            actor ActorServiceMock: ActorService {
                private struct Storage {
                    var initCallCount: Int = 0
                    var initCallArguments: [String] = []
                }
                private let _storage = MockableLock<Storage>(Storage())
                nonisolated var initCallCount: Int {
                    _storage.withLock {
                        $0.initCallCount
                    }
                }
                nonisolated var initCallArguments: [String] {
                    _storage.withLock {
                        $0.initCallArguments
                    }
                }
                init(id: String) {
                    _storage.withLock { storage in
                        storage.initCallCount += 1
                        storage.initCallArguments.append(id)
                    }
                }
                nonisolated func resetMock() {
                    _storage.withLock { storage in
                        storage.initCallCount = 0
                        storage.initCallArguments = []
                    }
                }
                static func resetMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("An init declared directly on an inheriting protocol is not yet supported")
    func inheritedInitializerDiagnostic() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol ChildService: BaseService {
                init(id: String)
            }
            """,
            expandedSource: """
            protocol ChildService: BaseService {
                init(id: String)
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "init requirements declared on an inheriting protocol are not yet supported",
                    line: 3,
                    column: 5
                )
            ],
            macros: testMacros
        )
    }

    @Test("A child mock inherits the parent mock's initializers instead of synthesizing its own")
    func childMockInheritsParentInitializer() {
        // The parent's `init` requirement is satisfied by the inherited `required init`; the
        // child does not (and must not) re-declare it, so no synthesized `init()` is emitted.
        assertMacroExpansionForTesting(
            """
            @Mockable
            public protocol ChildOfInitBase: InitBase {
                func childMethod()
            }
            """,
            expandedSource: """
            public protocol ChildOfInitBase: InitBase {
                func childMethod()
            }

            #if DEBUG
            open class ChildOfInitBaseMock: InitBaseMock, ChildOfInitBase {
                public private(set) var childMethodCallCount: Int = 0
                @available(*, deprecated, message: "childMethod records no arguments; use childMethodCallCount instead.")
                public var childMethodCallArguments: [()] {
                    Array(repeating: (), count: childMethodCallCount)
                }
                public var childMethodHandler: (() -> Void)? = nil
                public func childMethod() {
                    childMethodCallCount += 1
                    if let _handler = childMethodHandler {
                        _handler()
                    }
                }
                open override func resetMock() {
                    super.resetMock()
                    childMethodCallCount = 0
                    childMethodHandler = nil
                }
                open override class func resetMock() {
                    super.resetMock()
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }
}
