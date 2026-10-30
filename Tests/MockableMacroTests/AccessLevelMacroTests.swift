import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import MockableMacros

@Suite("Access Level Macro Tests")
struct AccessLevelMacroTests {
    private let testMacros: [String: Macro.Type] = [
        "Mockable": MockableMacro.self
    ]

    @Test("Internal protocol generates mock without explicit access modifier")
    func internalProtocol() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol InternalService {
                func fetch() -> String
            }
            """,
            expandedSource: """
            protocol InternalService {
                func fetch() -> String
            }

            #if DEBUG
            class InternalServiceMock: InternalService {
                private(set) var fetchCallCount: Int = 0
                @available(*, deprecated, message: "fetch records no arguments; use fetchCallCount instead.")
                var fetchCallArguments: [()] {
                    Array(repeating: (), count: fetchCallCount)
                }
                var fetchHandler: (() -> String)? = nil
                func fetch() -> String {
                    fetchCallCount += 1
                    guard let _handler = fetchHandler else {
                        fatalError("\\(Self.self).fetchHandler is not set")
                    }
                    return _handler()
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

    @Test("Public protocol generates open mock class")
    func publicProtocol() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            public protocol PublicService {
                func fetch() -> String
            }
            """,
            expandedSource: """
            public protocol PublicService {
                func fetch() -> String
            }

            #if DEBUG
            open class PublicServiceMock: PublicService {
                public init() {
                }
                public private(set) var fetchCallCount: Int = 0
                @available(*, deprecated, message: "fetch records no arguments; use fetchCallCount instead.")
                public var fetchCallArguments: [()] {
                    Array(repeating: (), count: fetchCallCount)
                }
                public var fetchHandler: (() -> String)? = nil
                public func fetch() -> String {
                    fetchCallCount += 1
                    guard let _handler = fetchHandler else {
                        fatalError("\\(Self.self).fetchHandler is not set")
                    }
                    return _handler()
                }
                open func resetMock() {
                    fetchCallCount = 0
                    fetchHandler = nil
                }
                open class func resetStaticMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Package protocol generates package mock")
    func packageProtocol() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            package protocol PackageService {
                func fetch() -> String
            }
            """,
            expandedSource: """
            package protocol PackageService {
                func fetch() -> String
            }

            #if DEBUG
            package class PackageServiceMock: PackageService {
                package init() {
                }
                package private(set) var fetchCallCount: Int = 0
                @available(*, deprecated, message: "fetch records no arguments; use fetchCallCount instead.")
                package var fetchCallArguments: [()] {
                    Array(repeating: (), count: fetchCallCount)
                }
                package var fetchHandler: (() -> String)? = nil
                package func fetch() -> String {
                    fetchCallCount += 1
                    guard let _handler = fetchHandler else {
                        fatalError("\\(Self.self).fetchHandler is not set")
                    }
                    return _handler()
                }
                package func resetMock() {
                    fetchCallCount = 0
                    fetchHandler = nil
                }
                package class func resetStaticMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Internal protocol with property generates mock without explicit access modifier")
    func internalProtocolWithProperty() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol InternalConfig {
                var apiKey: String { get }
            }
            """,
            expandedSource: """
            protocol InternalConfig {
                var apiKey: String { get }
            }

            #if DEBUG
            class InternalConfigMock: InternalConfig {
                private var _apiKey: String? = nil
                var apiKey: String {
                    get {
                        _apiKey!
                    }
                    set {
                        _apiKey = newValue
                    }
                }
                func resetMock() {
                    _apiKey = nil
                }
                class func resetStaticMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Public protocol with property generates open mock class")
    func publicProtocolWithProperty() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            public protocol PublicConfig {
                var apiKey: String { get }
            }
            """,
            expandedSource: """
            public protocol PublicConfig {
                var apiKey: String { get }
            }

            #if DEBUG
            open class PublicConfigMock: PublicConfig {
                public init() {
                }
                private var _apiKey: String? = nil
                public var apiKey: String {
                    get {
                        _apiKey!
                    }
                    set {
                        _apiKey = newValue
                    }
                }
                open func resetMock() {
                    _apiKey = nil
                }
                open class func resetStaticMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    // MARK: - Edge Cases: fileprivate and private protocols

    @Test("Fileprivate protocol generates fileprivate mock")
    func fileprivateProtocol() {
        // fileprivate protocols can only be adopted within the same file.
        // While this is a rare use case, the macro correctly respects the access level.
        assertMacroExpansionForTesting(
            """
            @Mockable
            fileprivate protocol FileprivateService {
                func fetch() -> String
            }
            """,
            expandedSource: """
            fileprivate protocol FileprivateService {
                func fetch() -> String
            }

            #if DEBUG
            fileprivate class FileprivateServiceMock: FileprivateService {
                fileprivate private(set) var fetchCallCount: Int = 0
                @available(*, deprecated, message: "fetch records no arguments; use fetchCallCount instead.")
                fileprivate var fetchCallArguments: [()] {
                    Array(repeating: (), count: fetchCallCount)
                }
                fileprivate var fetchHandler: (() -> String)? = nil
                fileprivate func fetch() -> String {
                    fetchCallCount += 1
                    guard let _handler = fetchHandler else {
                        fatalError("\\(Self.self).fetchHandler is not set")
                    }
                    return _handler()
                }
                fileprivate func resetMock() {
                    fetchCallCount = 0
                    fetchHandler = nil
                }
                fileprivate class func resetStaticMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Private protocol generates private mock")
    func privateProtocol() {
        // private protocols can only be adopted within the same enclosing declaration.
        // While this is a rare use case, the macro correctly respects the access level.
        // Note: The class is `private`, but members must be `fileprivate` to satisfy
        // the protocol requirements (a Swift language requirement).
        assertMacroExpansionForTesting(
            """
            @Mockable
            private protocol PrivateService {
                func fetch() -> String
            }
            """,
            expandedSource: """
            private protocol PrivateService {
                func fetch() -> String
            }

            #if DEBUG
            private class PrivateServiceMock: PrivateService {
                fileprivate private(set) var fetchCallCount: Int = 0
                @available(*, deprecated, message: "fetch records no arguments; use fetchCallCount instead.")
                fileprivate var fetchCallArguments: [()] {
                    Array(repeating: (), count: fetchCallCount)
                }
                fileprivate var fetchHandler: (() -> String)? = nil
                fileprivate func fetch() -> String {
                    fetchCallCount += 1
                    guard let _handler = fetchHandler else {
                        fatalError("\\(Self.self).fetchHandler is not set")
                    }
                    return _handler()
                }
                fileprivate func resetMock() {
                    fetchCallCount = 0
                    fetchHandler = nil
                }
                fileprivate class func resetStaticMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }
}
