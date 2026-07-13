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
                var initCallCount: Int = 0
                var initCallArgs: [String] = []
                required init(id: String) {
                    initCallCount += 1
                    initCallArgs.append(id)
                }
                var fetchCallCount: Int = 0
                var fetchCallArgs: [()] = []
                var fetchHandler: (@Sendable () -> Int)? = nil
                func fetch() -> Int {
                    fetchCallCount += 1
                    fetchCallArgs.append(())
                    guard let _handler = fetchHandler else {
                        fatalError("\\(Self.self).fetchHandler is not set")
                    }
                    return _handler()
                }
                func resetMock() {
                    initCallCount = 0
                    initCallArgs = []
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
                var initCallCount: Int = 0
                var initCallArgs: [()] = []
                required init() {
                    initCallCount += 1
                    initCallArgs.append(())
                }
                func resetMock() {
                    initCallCount = 0
                    initCallArgs = []
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
                var initCallCount: Int = 0
                var initCallArgs: [(host: String, port: Int)] = []
                required init(host: String, port: Int) {
                    initCallCount += 1
                    initCallArgs.append((host: host, port: port))
                }
                func resetMock() {
                    initCallCount = 0
                    initCallArgs = []
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
                var initStringCallCount: Int = 0
                var initStringCallArgs: [String] = []
                required init(host: String) {
                    initStringCallCount += 1
                    initStringCallArgs.append(host)
                }
                var initStringIntCallCount: Int = 0
                var initStringIntCallArgs: [(host: String, port: Int)] = []
                required init(host: String, port: Int) {
                    initStringIntCallCount += 1
                    initStringIntCallArgs.append((host: host, port: port))
                }
                func resetMock() {
                    initStringCallCount = 0
                    initStringCallArgs = []
                    initStringIntCallCount = 0
                    initStringIntCallArgs = []
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
                var initCallCount: Int = 0
                var initCallArgs: [String] = []
                required init(path: String) throws {
                    initCallCount += 1
                    initCallArgs.append(path)
                }
                func resetMock() {
                    initCallCount = 0
                    initCallArgs = []
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
                var initCallCount: Int = 0
                var initCallArgs: [String] = []
                required init?(raw: String) {
                    initCallCount += 1
                    initCallArgs.append(raw)
                }
                func resetMock() {
                    initCallCount = 0
                    initCallArgs = []
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
                public var initCallCount: Int = 0
                public var initCallArgs: [String] = []
                public required init(token: String) {
                    initCallCount += 1
                    initCallArgs.append(token)
                }
                open func resetMock() {
                    initCallCount = 0
                    initCallArgs = []
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
                var _name: String? = nil
                var name: String {
                    _name!
                }
                var initCallCount: Int = 0
                var initCallArgs: [String] = []
                required init(name: String) {
                    initCallCount += 1
                    initCallArgs.append(name)
                }
                func resetMock() {
                    _name = nil
                    initCallCount = 0
                    initCallArgs = []
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
                var initCallCount: Int = 0
                var initCallArgs: [String] = []
                required init(title: String) {
                    initCallCount += 1
                    initCallArgs.append(title)
                }
                func resetMock() {
                    initCallCount = 0
                    initCallArgs = []
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
                    var initCallArgs: [String] = []
                }
                private let _storage = MockableLock<Storage>(Storage())
                var initCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.initCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.initCallCount = newValue
                        }
                    }
                }
                var initCallArgs: [String] {
                    get {
                        _storage.withLock {
                            $0.initCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.initCallArgs = newValue
                        }
                    }
                }
                required init(id: String) {
                    _storage.withLock { storage in
                        storage.initCallCount += 1
                        storage.initCallArgs.append(id)
                    }
                }
                func resetMock() {
                    _storage.withLock { storage in
                        storage.initCallCount = 0
                        storage.initCallArgs = []
                    }
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
                    var initCallArgs: [String] = []
                }
                private let _storage = MockableLock<Storage>(Storage())
                nonisolated var initCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.initCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.initCallCount = newValue
                        }
                    }
                }
                nonisolated var initCallArgs: [String] {
                    get {
                        _storage.withLock {
                            $0.initCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.initCallArgs = newValue
                        }
                    }
                }
                init(id: String) {
                    _storage.withLock { storage in
                        storage.initCallCount += 1
                        storage.initCallArgs.append(id)
                    }
                }
                nonisolated func resetMock() {
                    _storage.withLock { storage in
                        storage.initCallCount = 0
                        storage.initCallArgs = []
                    }
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Init requirement on an inheriting protocol is not yet supported")
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
                    message: "init requirements are not yet supported for inheriting protocols",
                    line: 3,
                    column: 5
                )
            ],
            macros: testMacros
        )
    }
}
