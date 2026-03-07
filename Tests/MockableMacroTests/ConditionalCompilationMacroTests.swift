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
            class KeychainManagerMock: KeychainManager {
                var getDeviceIdCallCount: Int = 0
                var getDeviceIdCallArgs: [()] = []
                var getDeviceIdHandler: (@Sendable () -> String?)? = nil
                func getDeviceId() -> String? {
                    getDeviceIdCallCount += 1
                    getDeviceIdCallArgs.append(())
                    guard let _handler = getDeviceIdHandler else {
                        fatalError("\\(Self.self).getDeviceIdHandler is not set")
                    }
                    return _handler()
                }
                var saveAccessIdCallCount: Int = 0
                var saveAccessIdCallArgs: [String] = []
                var saveAccessIdHandler: (@Sendable (String) -> Void)? = nil
                func saveAccessId(_ accessId: String) {
                    saveAccessIdCallCount += 1
                    saveAccessIdCallArgs.append(accessId)
                    if let _handler = saveAccessIdHandler {
                        _handler(accessId)
                    }
                }
                #if DEBUG
                var deleteDeviceIdCallCount: Int = 0
                var deleteDeviceIdCallArgs: [()] = []
                var deleteDeviceIdHandler: (@Sendable () -> Void)? = nil
                func deleteDeviceId() {
                    deleteDeviceIdCallCount += 1
                    deleteDeviceIdCallArgs.append(())
                    if let _handler = deleteDeviceIdHandler {
                        _handler()
                    }
                }
                var getAllObjectsCallCount: Int = 0
                var getAllObjectsCallArgs: [()] = []
                var getAllObjectsHandler: (@Sendable () -> [AnyObject])? = nil
                func getAllObjects() -> [AnyObject] {
                    getAllObjectsCallCount += 1
                    getAllObjectsCallArgs.append(())
                    guard let _handler = getAllObjectsHandler else {
                        fatalError("\\(Self.self).getAllObjectsHandler is not set")
                    }
                    return _handler()
                }
                #endif
                func resetMock() {
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
            class DebugServiceMock: DebugService {
                var _isEnabled: Bool? = nil
                var isEnabled: Bool {
                    _isEnabled!
                }
                #if DEBUG
                var _debugInfo: String? = nil
                var debugInfo: String {
                    get {
                        _debugInfo!
                    }
                    set {
                        _debugInfo = newValue
                    }
                }
                #endif
                func resetMock() {
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

    @Test("Protocol with #elseif and #else conditional compilation")
    func conditionalCompilationWithElseIfAndElse() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol PlatformLogger {
                #if os(iOS)
                func logToConsole()
                #elseif os(macOS)
                func logToFile()
                #else
                func logToFallback()
                #endif
            }
            """,
            expandedSource: """
            protocol PlatformLogger {
                #if os(iOS)
                func logToConsole()
                #elseif os(macOS)
                func logToFile()
                #else
                func logToFallback()
                #endif
            }

            #if DEBUG
            class PlatformLoggerMock: PlatformLogger {
                #if os(iOS)
                var logToConsoleCallCount: Int = 0
                var logToConsoleCallArgs: [()] = []
                var logToConsoleHandler: (@Sendable () -> Void)? = nil
                func logToConsole() {
                    logToConsoleCallCount += 1
                    logToConsoleCallArgs.append(())
                    if let _handler = logToConsoleHandler {
                        _handler()
                    }
                }
                #elseif os(macOS)
                var logToFileCallCount: Int = 0
                var logToFileCallArgs: [()] = []
                var logToFileHandler: (@Sendable () -> Void)? = nil
                func logToFile() {
                    logToFileCallCount += 1
                    logToFileCallArgs.append(())
                    if let _handler = logToFileHandler {
                        _handler()
                    }
                }
                #else
                var logToFallbackCallCount: Int = 0
                var logToFallbackCallArgs: [()] = []
                var logToFallbackHandler: (@Sendable () -> Void)? = nil
                func logToFallback() {
                    logToFallbackCallCount += 1
                    logToFallbackCallArgs.append(())
                    if let _handler = logToFallbackHandler {
                        _handler()
                    }
                }
                #endif
                func resetMock() {
                    #if os(iOS)
                    logToConsoleCallCount = 0
                    logToConsoleCallArgs = []
                    logToConsoleHandler = nil
                    #elseif os(macOS)
                    logToFileCallCount = 0
                    logToFileCallArgs = []
                    logToFileHandler = nil
                    #else
                    logToFallbackCallCount = 0
                    logToFallbackCallArgs = []
                    logToFallbackHandler = nil
                    #endif
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("Sendable protocol with #elseif and #else conditional compilation")
    func sendableConditionalCompilationWithElseIfAndElse() {
        assertMacroExpansionForTesting(
            """
            @Mockable(legacyLock: true)
            protocol ThreadSafePlatformLogger: Sendable {
                #if os(iOS)
                func logToConsole()
                #elseif os(macOS)
                func logToFile()
                #else
                func logToFallback()
                #endif
            }
            """,
            expandedSource: """
            protocol ThreadSafePlatformLogger: Sendable {
                #if os(iOS)
                func logToConsole()
                #elseif os(macOS)
                func logToFile()
                #else
                func logToFallback()
                #endif
            }

            #if DEBUG
            class ThreadSafePlatformLoggerMock: ThreadSafePlatformLogger, @unchecked Sendable {
                private struct Storage {
                    #if os(iOS)
                    var logToConsoleCallCount: Int = 0
                    var logToConsoleCallArgs: [()] = []
                    var logToConsoleHandler: (@Sendable () -> Void)? = nil
                    #elseif os(macOS)
                    var logToFileCallCount: Int = 0
                    var logToFileCallArgs: [()] = []
                    var logToFileHandler: (@Sendable () -> Void)? = nil
                    #else
                    var logToFallbackCallCount: Int = 0
                    var logToFallbackCallArgs: [()] = []
                    var logToFallbackHandler: (@Sendable () -> Void)? = nil
                    #endif
                }
                private let _storage = LegacyLock<Storage>(Storage())
                #if os(iOS)
                var logToConsoleCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.logToConsoleCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.logToConsoleCallCount = newValue
                        }
                    }
                }
                var logToConsoleCallArgs: [()] {
                    get {
                        _storage.withLock {
                            $0.logToConsoleCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.logToConsoleCallArgs = newValue
                        }
                    }
                }
                var logToConsoleHandler: (@Sendable () -> Void)? {
                    get {
                        _storage.withLock {
                            $0.logToConsoleHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.logToConsoleHandler = newValue
                        }
                    }
                }
                func logToConsole() {
                    let _handler = _storage.withLock { storage -> (@Sendable () -> Void)? in
                        storage.logToConsoleCallCount += 1
                        storage.logToConsoleCallArgs.append(())
                        return storage.logToConsoleHandler
                    }
                    if let _handler {
                        _handler()
                    }
                }
                #elseif os(macOS)
                var logToFileCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.logToFileCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.logToFileCallCount = newValue
                        }
                    }
                }
                var logToFileCallArgs: [()] {
                    get {
                        _storage.withLock {
                            $0.logToFileCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.logToFileCallArgs = newValue
                        }
                    }
                }
                var logToFileHandler: (@Sendable () -> Void)? {
                    get {
                        _storage.withLock {
                            $0.logToFileHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.logToFileHandler = newValue
                        }
                    }
                }
                func logToFile() {
                    let _handler = _storage.withLock { storage -> (@Sendable () -> Void)? in
                        storage.logToFileCallCount += 1
                        storage.logToFileCallArgs.append(())
                        return storage.logToFileHandler
                    }
                    if let _handler {
                        _handler()
                    }
                }
                #else
                var logToFallbackCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.logToFallbackCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.logToFallbackCallCount = newValue
                        }
                    }
                }
                var logToFallbackCallArgs: [()] {
                    get {
                        _storage.withLock {
                            $0.logToFallbackCallArgs
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.logToFallbackCallArgs = newValue
                        }
                    }
                }
                var logToFallbackHandler: (@Sendable () -> Void)? {
                    get {
                        _storage.withLock {
                            $0.logToFallbackHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.logToFallbackHandler = newValue
                        }
                    }
                }
                func logToFallback() {
                    let _handler = _storage.withLock { storage -> (@Sendable () -> Void)? in
                        storage.logToFallbackCallCount += 1
                        storage.logToFallbackCallArgs.append(())
                        return storage.logToFallbackHandler
                    }
                    if let _handler {
                        _handler()
                    }
                }
                #endif
                func resetMock() {
                    _storage.withLock { storage in
                        #if os(iOS)
                        storage.logToConsoleCallCount = 0
                        storage.logToConsoleCallArgs = []
                        storage.logToConsoleHandler = nil
                        #elseif os(macOS)
                        storage.logToFileCallCount = 0
                        storage.logToFileCallArgs = []
                        storage.logToFileHandler = nil
                        #else
                        storage.logToFallbackCallCount = 0
                        storage.logToFallbackCallArgs = []
                        storage.logToFallbackHandler = nil
                        #endif
                    }
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }
}
