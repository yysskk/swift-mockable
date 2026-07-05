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
                var loadCallCount: Int = 0
                var loadCallArgs: [Int] = []
                var loadHandler: (@Sendable (Int) throws -> String)? = nil
                func load(id: Int) throws(LoadError) -> String {
                    loadCallCount += 1
                    loadCallArgs.append(id)
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
                    loadCallArgs = []
                    loadHandler = nil
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
                var fetchCallCount: Int = 0
                var fetchCallArgs: [()] = []
                var fetchHandler: (@Sendable () async throws -> Data)? = nil
                func fetch() async throws(NetworkError) -> Data {
                    fetchCallCount += 1
                    fetchCallArgs.append(())
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
                    fetchCallArgs = []
                    fetchHandler = nil
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
                var runCallCount: Int = 0
                var runCallArgs: [()] = []
                var runHandler: (@Sendable (() throws -> Void) throws -> Void)? = nil
                func run<E: Error>(_ body: () throws(E) -> Void) throws(E) {
                    runCallCount += 1
                    runCallArgs.append(())
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
                    runCallArgs = []
                    runHandler = nil
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
                var runCallCount: Int = 0
                var runCallArgs: [() throws -> Void] = []
                var runHandler: (@Sendable (() throws -> Void) -> Void)? = nil
                func run(_ body: @escaping () throws(RunError) -> Void) {
                    runCallCount += 1
                    runCallArgs.append(body)
                    if let _handler = runHandler {
                        _handler(body)
                    }
                }
                func resetMock() {
                    runCallCount = 0
                    runCallArgs = []
                    runHandler = nil
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
                var settingCallCount: Int = 0
                var settingHandler: (@Sendable () throws -> Int)? = nil
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
            }
            #endif
            """,
            macros: testMacros
        )
    }
}
