import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import MockableMacros

// A requirement without arguments to record has no stored `CallArguments`: its call
// count is the whole call history. A deprecated computed `CallArguments` derived from
// the call count stays for one major release, so code reading it keeps compiling.

@Suite("Argumentless Call History Macro Tests")
struct ArgumentlessCallHistoryMacroTests {
    private let testMacros: [String: Macro.Type] = [
        "Mockable": MockableMacro.self
    ]

    @Test("A static requirement without arguments derives its deprecated CallArguments from the locked count")
    func staticRequirementWithoutArguments() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Heartbeat {
                static func ping()
                func beat(at time: Int)
            }
            """,
            expandedSource: """
            protocol Heartbeat {
                static func ping()
                func beat(at time: Int)
            }

            #if DEBUG
            class HeartbeatMock: Heartbeat {
                private struct StaticStorage {
                    var pingCallCount: Int = 0
                    var pingHandler: (@Sendable () -> Void)? = nil
                }
                private static let _staticStorage = MockableLock<StaticStorage>(StaticStorage())
                static var pingCallCount: Int {
                    _staticStorage.withLock {
                        $0.pingCallCount
                    }
                }
                @available(*, deprecated, message: "ping records no arguments; use pingCallCount instead.")
                static var pingCallArguments: [()] {
                    Array(repeating: (), count: pingCallCount)
                }
                static var pingHandler: (@Sendable () -> Void)? {
                    get {
                        _staticStorage.withLock {
                            $0.pingHandler
                        }
                    }
                    set {
                        _staticStorage.withLock {
                            $0.pingHandler = newValue
                        }
                    }
                }
                static func ping() {
                    let _handler = _staticStorage.withLock { storage -> (@Sendable () -> Void)? in
                        storage.pingCallCount += 1
                        return storage.pingHandler
                    }
                    if let _handler {
                        _handler()
                    }
                }
                private(set) var beatCallCount: Int = 0
                private(set) var beatCallArguments: [Int] = []
                var beatHandler: ((Int) -> Void)? = nil
                func beat(at time: Int) {
                    beatCallCount += 1
                    beatCallArguments.append(time)
                    if let _handler = beatHandler {
                        _handler(time)
                    }
                }
                func resetMock() {
                    beatCallCount = 0
                    beatCallArguments = []
                    beatHandler = nil
                }
                class func resetMock() {
                    Self._staticStorage.withLock { storage in
                        storage.pingCallCount = 0
                        storage.pingHandler = nil
                    }
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }
}
