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
                private(set) var getDeviceIdCallCount: Int = 0
                @available(*, deprecated, message: "getDeviceId records no arguments; use getDeviceIdCallCount instead.")
                var getDeviceIdCallArguments: [()] {
                    Array(repeating: (), count: getDeviceIdCallCount)
                }
                var getDeviceIdHandler: (() -> String?)? = nil
                func getDeviceId() -> String? {
                    getDeviceIdCallCount += 1
                    guard let _handler = getDeviceIdHandler else {
                        return nil
                    }
                    return _handler()
                }
                private(set) var saveAccessIdCallCount: Int = 0
                private(set) var saveAccessIdCallArguments: [String] = []
                var saveAccessIdHandler: ((String) -> Void)? = nil
                func saveAccessId(_ accessId: String) {
                    saveAccessIdCallCount += 1
                    saveAccessIdCallArguments.append(accessId)
                    if let _handler = saveAccessIdHandler {
                        _handler(accessId)
                    }
                }
                #if DEBUG
                private(set) var deleteDeviceIdCallCount: Int = 0
                @available(*, deprecated, message: "deleteDeviceId records no arguments; use deleteDeviceIdCallCount instead.")
                var deleteDeviceIdCallArguments: [()] {
                    Array(repeating: (), count: deleteDeviceIdCallCount)
                }
                var deleteDeviceIdHandler: (() -> Void)? = nil
                func deleteDeviceId() {
                    deleteDeviceIdCallCount += 1
                    if let _handler = deleteDeviceIdHandler {
                        _handler()
                    }
                }
                private(set) var getAllObjectsCallCount: Int = 0
                @available(*, deprecated, message: "getAllObjects records no arguments; use getAllObjectsCallCount instead.")
                var getAllObjectsCallArguments: [()] {
                    Array(repeating: (), count: getAllObjectsCallCount)
                }
                var getAllObjectsHandler: (() -> [AnyObject])? = nil
                func getAllObjects() -> [AnyObject] {
                    getAllObjectsCallCount += 1
                    guard let _handler = getAllObjectsHandler else {
                        return []
                    }
                    return _handler()
                }
                #endif
                func resetMock() {
                    getDeviceIdCallCount = 0
                    getDeviceIdHandler = nil
                    saveAccessIdCallCount = 0
                    saveAccessIdCallArguments = []
                    saveAccessIdHandler = nil
                    #if DEBUG
                    deleteDeviceIdCallCount = 0
                    deleteDeviceIdHandler = nil
                    getAllObjectsCallCount = 0
                    getAllObjectsHandler = nil
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
                private var _isEnabled: Bool? = nil
                var isEnabled: Bool {
                    get {
                        _isEnabled!
                    }
                    set {
                        _isEnabled = newValue
                    }
                }
                #if DEBUG
                private var _debugInfo: String? = nil
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
                class func resetStaticMock() {
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
                private(set) var logToConsoleCallCount: Int = 0
                @available(*, deprecated, message: "logToConsole records no arguments; use logToConsoleCallCount instead.")
                var logToConsoleCallArguments: [()] {
                    Array(repeating: (), count: logToConsoleCallCount)
                }
                var logToConsoleHandler: (() -> Void)? = nil
                func logToConsole() {
                    logToConsoleCallCount += 1
                    if let _handler = logToConsoleHandler {
                        _handler()
                    }
                }
                #elseif os(macOS)
                private(set) var logToFileCallCount: Int = 0
                @available(*, deprecated, message: "logToFile records no arguments; use logToFileCallCount instead.")
                var logToFileCallArguments: [()] {
                    Array(repeating: (), count: logToFileCallCount)
                }
                var logToFileHandler: (() -> Void)? = nil
                func logToFile() {
                    logToFileCallCount += 1
                    if let _handler = logToFileHandler {
                        _handler()
                    }
                }
                #else
                private(set) var logToFallbackCallCount: Int = 0
                @available(*, deprecated, message: "logToFallback records no arguments; use logToFallbackCallCount instead.")
                var logToFallbackCallArguments: [()] {
                    Array(repeating: (), count: logToFallbackCallCount)
                }
                var logToFallbackHandler: (() -> Void)? = nil
                func logToFallback() {
                    logToFallbackCallCount += 1
                    if let _handler = logToFallbackHandler {
                        _handler()
                    }
                }
                #endif
                func resetMock() {
                    #if os(iOS)
                    logToConsoleCallCount = 0
                    logToConsoleHandler = nil
                    #elseif os(macOS)
                    logToFileCallCount = 0
                    logToFileHandler = nil
                    #else
                    logToFallbackCallCount = 0
                    logToFallbackHandler = nil
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

    @Test("Sendable protocol with #elseif and #else conditional compilation")
    func sendableConditionalCompilationWithElseIfAndElse() {
        assertMacroExpansionForTesting(
            """
            @Mockable
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
                    var logToConsoleHandler: (@Sendable () -> Void)? = nil
                    #elseif os(macOS)
                    var logToFileCallCount: Int = 0
                    var logToFileHandler: (@Sendable () -> Void)? = nil
                    #else
                    var logToFallbackCallCount: Int = 0
                    var logToFallbackHandler: (@Sendable () -> Void)? = nil
                    #endif
                }
                private let _storage = _MockableLock<Storage>(Storage())
                #if os(iOS)
                var logToConsoleCallCount: Int {
                    _storage.withLock {
                        $0.logToConsoleCallCount
                    }
                }
                @available(*, deprecated, message: "logToConsole records no arguments; use logToConsoleCallCount instead.")
                var logToConsoleCallArguments: [()] {
                    Array(repeating: (), count: logToConsoleCallCount)
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
                        return storage.logToConsoleHandler
                    }
                    if let _handler {
                        _handler()
                    }
                }
                #elseif os(macOS)
                var logToFileCallCount: Int {
                    _storage.withLock {
                        $0.logToFileCallCount
                    }
                }
                @available(*, deprecated, message: "logToFile records no arguments; use logToFileCallCount instead.")
                var logToFileCallArguments: [()] {
                    Array(repeating: (), count: logToFileCallCount)
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
                        return storage.logToFileHandler
                    }
                    if let _handler {
                        _handler()
                    }
                }
                #else
                var logToFallbackCallCount: Int {
                    _storage.withLock {
                        $0.logToFallbackCallCount
                    }
                }
                @available(*, deprecated, message: "logToFallback records no arguments; use logToFallbackCallCount instead.")
                var logToFallbackCallArguments: [()] {
                    Array(repeating: (), count: logToFallbackCallCount)
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
                        storage.logToConsoleHandler = nil
                        #elseif os(macOS)
                        storage.logToFileCallCount = 0
                        storage.logToFileHandler = nil
                        #else
                        storage.logToFallbackCallCount = 0
                        storage.logToFallbackHandler = nil
                        #endif
                    }
                }
                class func resetStaticMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }
}
