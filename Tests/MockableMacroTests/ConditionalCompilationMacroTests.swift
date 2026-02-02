import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import MockableMacros

@Suite("Conditional Compilation Macro Tests")
struct ConditionalCompilationMacroTests {
    let testMacros: [String: Macro.Type] = [
        "Mockable": MockableMacro.self
    ]

    @Test("Protocol with #if DEBUG conditional compilation")
    func conditionalCompilationDebug() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol KeychainManager {
                func getDeviceId() -> String?
                func saveAccessId(_ accessId: String)

                #if DEBUG
                func deleteDeviceId()
                func getAllObjects() -> [AnyObject]
                #endif
            }
            """,
            expandedSource: """
            protocol KeychainManager {
                func getDeviceId() -> String?
                func saveAccessId(_ accessId: String)

                #if DEBUG
                func deleteDeviceId()
                func getAllObjects() -> [AnyObject]
                #endif
            }

            #if DEBUG
            public class KeychainManagerMock: KeychainManager {
                public var getDeviceIdCallCount: Int = 0
                public var getDeviceIdCallArgs: [()] = []
                public var getDeviceIdHandler: (@Sendable () -> String?)? = nil
                public func getDeviceId() -> String? {
                    getDeviceIdCallCount += 1
                    getDeviceIdCallArgs.append(())
                    guard let _handler = getDeviceIdHandler else {
                        fatalError("\\(Self.self).getDeviceIdHandler is not set")
                    }
                    return _handler()
                }
                public var saveAccessIdCallCount: Int = 0
                public var saveAccessIdCallArgs: [String] = []
                public var saveAccessIdHandler: (@Sendable (String) -> Void)? = nil
                public func saveAccessId(_ accessId: String) {
                    saveAccessIdCallCount += 1
                    saveAccessIdCallArgs.append(accessId)
                    if let _handler = saveAccessIdHandler {
                        _handler(accessId)
                    }
                }
                #if DEBUG
                public var deleteDeviceIdCallCount: Int = 0
                public var deleteDeviceIdCallArgs: [()] = []
                public var deleteDeviceIdHandler: (@Sendable () -> Void)? = nil
                public func deleteDeviceId() {
                    deleteDeviceIdCallCount += 1
                    deleteDeviceIdCallArgs.append(())
                    if let _handler = deleteDeviceIdHandler {
                        _handler()
                    }
                }
                public var getAllObjectsCallCount: Int = 0
                public var getAllObjectsCallArgs: [()] = []
                public var getAllObjectsHandler: (@Sendable () -> [AnyObject])? = nil
                public func getAllObjects() -> [AnyObject] {
                    getAllObjectsCallCount += 1
                    getAllObjectsCallArgs.append(())
                    guard let _handler = getAllObjectsHandler else {
                        fatalError("\\(Self.self).getAllObjectsHandler is not set")
                    }
                    return _handler()
                }
                #endif
                public func resetMock() {
                    getDeviceIdCallCount = 0
                    getDeviceIdCallArgs = []
                    getDeviceIdHandler = nil
                    saveAccessIdCallCount = 0
                    saveAccessIdCallArgs = []
                    saveAccessIdHandler = nil
                    #if DEBUG
                    deleteDeviceIdCallCount = 0
                    deleteDeviceIdCallArgs = []
                    deleteDeviceIdHandler = nil
                    getAllObjectsCallCount = 0
                    getAllObjectsCallArgs = []
                    getAllObjectsHandler = nil
                    #endif
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Protocol with #if DEBUG containing properties")
    func conditionalCompilationWithProperties() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol DebugService {
                var isEnabled: Bool { get }

                #if DEBUG
                var debugInfo: String { get set }
                #endif
            }
            """,
            expandedSource: """
            protocol DebugService {
                var isEnabled: Bool { get }

                #if DEBUG
                var debugInfo: String { get set }
                #endif
            }

            #if DEBUG
            public class DebugServiceMock: DebugService {
                public var _isEnabled: Bool? = nil
                public var isEnabled: Bool {
                    _isEnabled!
                }
                #if DEBUG
                public var _debugInfo: String? = nil
                public var debugInfo: String {
                    get {
                        _debugInfo!
                    }
                    set {
                        _debugInfo = newValue
                    }
                }
                #endif
                public func resetMock() {
                    _isEnabled = nil
                    #if DEBUG
                    _debugInfo = nil
                    #endif
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }
}
