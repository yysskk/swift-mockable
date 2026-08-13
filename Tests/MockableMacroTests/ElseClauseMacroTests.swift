import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import MockableMacros

/// Requirements declared only in an `#else` clause. Member generation maps every
/// clause, so the whole-protocol analyses (type-member detection, overload grouping,
/// initializer detection) have to see those requirements as well.
@Suite("Else Clause Macro Tests")
struct ElseClauseMacroTests {
    let testMacros: [String: Macro.Type] = [
        "Mockable": MockableMacro.self
    ]

    @Test("A static requirement declared only in an #else clause gets its static storage")
    func staticRequirementInElseClause() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Service {
                #if CUSTOM
                func alpha()
                #else
                static func beta() -> Int
                #endif
            }
            """,
            expandedSource: """
            protocol Service {
                #if CUSTOM
                func alpha()
                #else
                static func beta() -> Int
                #endif
            }

            #if DEBUG
            class ServiceMock: Service {
                private struct StaticStorage {
                    #if CUSTOM
                    #else
                    var betaCallCount: Int = 0
                    var betaCallArgs: [()] = []
                    var betaHandler: (@Sendable () -> Int)? = nil
                    #endif
                }
                private static let _staticStorage = MockableLock<StaticStorage>(StaticStorage())
                #if CUSTOM
                var alphaCallCount: Int = 0
                var alphaCallArgs: [()] = []
                var alphaHandler: (@Sendable () -> Void)? = nil
                func alpha() {
                    alphaCallCount += 1
                    alphaCallArgs.append(())
                    if let _handler = alphaHandler {
                        _handler()
                    }
                }
                #else
                static var betaCallCount: Int {
                    get {
                        _staticStorage.withLock {
                            $0.betaCallCount
                        }
                    }
                    set {
                        _staticStorage.withLock {
                            $0.betaCallCount = newValue
                        }
                    }
                }
                static var betaCallArgs: [()] {
                    get {
                        _staticStorage.withLock {
                            $0.betaCallArgs
                        }
                    }
                    set {
                        _staticStorage.withLock {
                            $0.betaCallArgs = newValue
                        }
                    }
                }
                static var betaHandler: (@Sendable () -> Int)? {
                    get {
                        _staticStorage.withLock {
                            $0.betaHandler
                        }
                    }
                    set {
                        _staticStorage.withLock {
                            $0.betaHandler = newValue
                        }
                    }
                }
                static func beta() -> Int {
                    let _handler = _staticStorage.withLock { storage -> (@Sendable () -> Int)? in
                        storage.betaCallCount += 1
                        storage.betaCallArgs.append(())
                        return storage.betaHandler
                    }
                    guard let _handler else {
                        fatalError("\\(Self.self).betaHandler is not set")
                    }
                    return _handler()
                }
                #endif
                func resetMock() {
                    #if CUSTOM
                    alphaCallCount = 0
                    alphaCallArgs = []
                    alphaHandler = nil
                    #else
                    #endif
                    Self._staticStorage.withLock { storage in
                        #if CUSTOM
                        #else
                        storage.betaCallCount = 0
                        storage.betaCallArgs = []
                        storage.betaHandler = nil
                        #endif
                    }
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Overloads declared only in an #else clause get distinct tracking members")
    func overloadsInElseClause() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Service {
                #if CUSTOM
                func alpha()
                #else
                func fetch(id: Int) -> Int
                func fetch(name: String) -> Int
                #endif
            }
            """,
            expandedSource: """
            protocol Service {
                #if CUSTOM
                func alpha()
                #else
                func fetch(id: Int) -> Int
                func fetch(name: String) -> Int
                #endif
            }

            #if DEBUG
            class ServiceMock: Service {
                #if CUSTOM
                var alphaCallCount: Int = 0
                var alphaCallArgs: [()] = []
                var alphaHandler: (@Sendable () -> Void)? = nil
                func alpha() {
                    alphaCallCount += 1
                    alphaCallArgs.append(())
                    if let _handler = alphaHandler {
                        _handler()
                    }
                }
                #else
                var fetchIntCallCount: Int = 0
                var fetchIntCallArgs: [Int] = []
                var fetchIntHandler: (@Sendable (Int) -> Int)? = nil
                func fetch(id: Int) -> Int {
                    fetchIntCallCount += 1
                    fetchIntCallArgs.append(id)
                    guard let _handler = fetchIntHandler else {
                        fatalError("\\(Self.self).fetchIntHandler is not set")
                    }
                    return _handler(id)
                }
                var fetchStringCallCount: Int = 0
                var fetchStringCallArgs: [String] = []
                var fetchStringHandler: (@Sendable (String) -> Int)? = nil
                func fetch(name: String) -> Int {
                    fetchStringCallCount += 1
                    fetchStringCallArgs.append(name)
                    guard let _handler = fetchStringHandler else {
                        fatalError("\\(Self.self).fetchStringHandler is not set")
                    }
                    return _handler(name)
                }
                #endif
                func resetMock() {
                    #if CUSTOM
                    alphaCallCount = 0
                    alphaCallArgs = []
                    alphaHandler = nil
                    #else
                    fetchIntCallCount = 0
                    fetchIntCallArgs = []
                    fetchIntHandler = nil
                    fetchStringCallCount = 0
                    fetchStringCallArgs = []
                    fetchStringHandler = nil
                    #endif
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("An init requirement declared only in an #else clause suppresses the synthesized init")
    func initializerInElseClause() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            public protocol Service {
                #if CUSTOM
                func alpha()
                #else
                init(name: String)
                #endif
            }
            """,
            expandedSource: """
            public protocol Service {
                #if CUSTOM
                func alpha()
                #else
                init(name: String)
                #endif
            }

            #if DEBUG
            open class ServiceMock: Service {
                #if CUSTOM
                public var alphaCallCount: Int = 0
                public var alphaCallArgs: [()] = []
                public var alphaHandler: (@Sendable () -> Void)? = nil
                public func alpha() {
                    alphaCallCount += 1
                    alphaCallArgs.append(())
                    if let _handler = alphaHandler {
                        _handler()
                    }
                }
                #else
                public var initCallCount: Int = 0
                public var initCallArgs: [String] = []
                public required init(name: String) {
                    initCallCount += 1
                    initCallArgs.append(name)
                }
                #endif
                open func resetMock() {
                    #if CUSTOM
                    alphaCallCount = 0
                    alphaCallArgs = []
                    alphaHandler = nil
                    #else
                    initCallCount = 0
                    initCallArgs = []
                    #endif
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }
}
