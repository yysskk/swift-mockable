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
                    var betaCallArguments: [()] = []
                    var betaHandler: (@Sendable () -> Int)? = nil
                    #endif
                }
                private static let _staticStorage = MockableLock<StaticStorage>(StaticStorage())
                #if CUSTOM
                private(set) var alphaCallCount: Int = 0
                private(set) var alphaCallArguments: [()] = []
                var alphaHandler: (() -> Void)? = nil
                func alpha() {
                    alphaCallCount += 1
                    alphaCallArguments.append(())
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
                static var betaCallArguments: [()] {
                    _staticStorage.withLock {
                        $0.betaCallArguments
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
                        storage.betaCallArguments.append(())
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
                    alphaCallArguments = []
                    alphaHandler = nil
                    #else
                    #endif
                }
                class func resetMock() {
                    Self._staticStorage.withLock { storage in
                        #if CUSTOM
                        #else
                        storage.betaCallCount = 0
                        storage.betaCallArguments = []
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
                private(set) var alphaCallArguments: [()] = []
                var alphaHandler: (() -> Void)? = nil
                func alpha() {
                    alphaCallCount += 1
                    alphaCallArguments.append(())
                    if let _handler = alphaHandler {
                        _handler()
                    }
                }
                #else
                private(set) var fetchIntCallCount: Int = 0
                private(set) var fetchIntCallArguments: [Int] = []
                var fetchIntHandler: ((Int) -> Int)? = nil
                func fetch(id: Int) -> Int {
                    fetchIntCallCount += 1
                    fetchIntCallArguments.append(id)
                    guard let _handler = fetchIntHandler else {
                        fatalError("\\(Self.self).fetchIntHandler is not set")
                    }
                    return _handler(id)
                }
                private(set) var fetchStringCallCount: Int = 0
                private(set) var fetchStringCallArguments: [String] = []
                var fetchStringHandler: ((String) -> Int)? = nil
                func fetch(name: String) -> Int {
                    fetchStringCallCount += 1
                    fetchStringCallArguments.append(name)
                    guard let _handler = fetchStringHandler else {
                        fatalError("\\(Self.self).fetchStringHandler is not set")
                    }
                    return _handler(name)
                }
                #endif
                func resetMock() {
                    #if CUSTOM
                    alphaCallCount = 0
                    alphaCallArguments = []
                    alphaHandler = nil
                    #else
                    fetchIntCallCount = 0
                    fetchIntCallArguments = []
                    fetchIntHandler = nil
                    fetchStringCallCount = 0
                    fetchStringCallArguments = []
                    fetchStringHandler = nil
                    #endif
                }
                class func resetMock() {
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
                public private(set) var alphaCallArguments: [()] = []
                public var alphaHandler: (() -> Void)? = nil
                public func alpha() {
                    alphaCallCount += 1
                    alphaCallArguments.append(())
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
                    alphaCallArguments = []
                    alphaHandler = nil
                    #else
                    initCallCount = 0
                    initCallArguments = []
                    #endif
                }
                open class func resetMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }
}
