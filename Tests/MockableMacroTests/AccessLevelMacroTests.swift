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
                var fetchCallCount: Int = 0
                var fetchCallArgs: [()] = []
                var fetchHandler: (@Sendable () -> String)? = nil
                func fetch() -> String {
                    fetchCallCount += 1
                    fetchCallArgs.append(())
                    guard let _handler = fetchHandler else {
                        fatalError("\\(Self.self).fetchHandler is not set")
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

    @Test("Public protocol generates public mock")
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
            public class PublicServiceMock: PublicService {
                public var fetchCallCount: Int = 0
                public var fetchCallArgs: [()] = []
                public var fetchHandler: (@Sendable () -> String)? = nil
                public func fetch() -> String {
                    fetchCallCount += 1
                    fetchCallArgs.append(())
                    guard let _handler = fetchHandler else {
                        fatalError("\\(Self.self).fetchHandler is not set")
                    }
                    return _handler()
                }
                public func resetMock() {
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
                package var fetchCallCount: Int = 0
                package var fetchCallArgs: [()] = []
                package var fetchHandler: (@Sendable () -> String)? = nil
                package func fetch() -> String {
                    fetchCallCount += 1
                    fetchCallArgs.append(())
                    guard let _handler = fetchHandler else {
                        fatalError("\\(Self.self).fetchHandler is not set")
                    }
                    return _handler()
                }
                package func resetMock() {
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
                var _apiKey: String? = nil
                var apiKey: String {
                    _apiKey!
                }
                func resetMock() {
                    _apiKey = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Public protocol with property generates public mock")
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
            public class PublicConfigMock: PublicConfig {
                public var _apiKey: String? = nil
                public var apiKey: String {
                    _apiKey!
                }
                public func resetMock() {
                    _apiKey = nil
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
                fileprivate var fetchCallCount: Int = 0
                fileprivate var fetchCallArgs: [()] = []
                fileprivate var fetchHandler: (@Sendable () -> String)? = nil
                fileprivate func fetch() -> String {
                    fetchCallCount += 1
                    fetchCallArgs.append(())
                    guard let _handler = fetchHandler else {
                        fatalError("\\(Self.self).fetchHandler is not set")
                    }
                    return _handler()
                }
                fileprivate func resetMock() {
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
                fileprivate var fetchCallCount: Int = 0
                fileprivate var fetchCallArgs: [()] = []
                fileprivate var fetchHandler: (@Sendable () -> String)? = nil
                fileprivate func fetch() -> String {
                    fetchCallCount += 1
                    fetchCallArgs.append(())
                    guard let _handler = fetchHandler else {
                        fatalError("\\(Self.self).fetchHandler is not set")
                    }
                    return _handler()
                }
                fileprivate func resetMock() {
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
}
