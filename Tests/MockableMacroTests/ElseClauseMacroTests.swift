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
                    var betaHandler: (@Sendable () -> Int)? = nil
                    #endif
                }
                private static let _staticStorage = MockableLock<StaticStorage>(StaticStorage())
                #if CUSTOM
                private(set) var alphaCallCount: Int = 0
                @available(*, deprecated, message: "alpha records no arguments; use alphaCallCount instead.")
                var alphaCallArguments: [()] {
                    Array(repeating: (), count: alphaCallCount)
                }
                var alphaHandler: (() -> Void)? = nil
                func alpha() {
                    alphaCallCount += 1
                    if let _handler = alphaHandler {
                        _handler()
                    }
                }
                #else
                static var betaCallCount: Int {
                    _staticStorage.withLock {
                        $0.betaCallCount
                    }
                }
                @available(*, deprecated, message: "beta records no arguments; use betaCallCount instead.")
                static var betaCallArguments: [()] {
                    Array(repeating: (), count: betaCallCount)
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
                    alphaHandler = nil
                    #else
                    #endif
                }
                class func resetStaticMock() {
                    Self._staticStorage.withLock { storage in
                        #if CUSTOM
                        #else
                        storage.betaCallCount = 0
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
                private(set) var alphaCallCount: Int = 0
                @available(*, deprecated, message: "alpha records no arguments; use alphaCallCount instead.")
                var alphaCallArguments: [()] {
                    Array(repeating: (), count: alphaCallCount)
                }
                var alphaHandler: (() -> Void)? = nil
                func alpha() {
                    alphaCallCount += 1
                    if let _handler = alphaHandler {
                        _handler()
                    }
                }
                #else
                private(set) var fetchIDCallCount: Int = 0
                private(set) var fetchIDCallArguments: [Int] = []
                var fetchIDHandler: ((Int) -> Int)? = nil
                func fetch(id: Int) -> Int {
                    fetchIDCallCount += 1
                    fetchIDCallArguments.append(id)
                    guard let _handler = fetchIDHandler else {
                        fatalError("\\(Self.self).fetchIDHandler is not set")
                    }
                    return _handler(id)
                }
                private(set) var fetchNameCallCount: Int = 0
                private(set) var fetchNameCallArguments: [String] = []
                var fetchNameHandler: ((String) -> Int)? = nil
                func fetch(name: String) -> Int {
                    fetchNameCallCount += 1
                    fetchNameCallArguments.append(name)
                    guard let _handler = fetchNameHandler else {
                        fatalError("\\(Self.self).fetchNameHandler is not set")
                    }
                    return _handler(name)
                }
                #endif
                func resetMock() {
                    #if CUSTOM
                    alphaCallCount = 0
                    alphaHandler = nil
                    #else
                    fetchIDCallCount = 0
                    fetchIDCallArguments = []
                    fetchIDHandler = nil
                    fetchNameCallCount = 0
                    fetchNameCallArguments = []
                    fetchNameHandler = nil
                    #endif
                }
                class func resetStaticMock() {
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
                public private(set) var alphaCallCount: Int = 0
                @available(*, deprecated, message: "alpha records no arguments; use alphaCallCount instead.")
                public var alphaCallArguments: [()] {
                    Array(repeating: (), count: alphaCallCount)
                }
                public var alphaHandler: (() -> Void)? = nil
                public func alpha() {
                    alphaCallCount += 1
                    if let _handler = alphaHandler {
                        _handler()
                    }
                }
                #else
                public private(set) var initCallCount: Int = 0
                public private(set) var initCallArguments: [String] = []
                public required init(name: String) {
                    initCallCount += 1
                    initCallArguments.append(name)
                }
                #endif
                open func resetMock() {
                    #if CUSTOM
                    alphaCallCount = 0
                    alphaHandler = nil
                    #else
                    initCallCount = 0
                    initCallArguments = []
                    #endif
                }
                open class func resetStaticMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }
}
