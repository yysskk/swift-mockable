import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import MockableMacros

/// Requirements of different kinds whose tracking identifiers would otherwise coincide:
/// an overload's suffixed identifier can spell out another requirement's own name.
@Suite("Tracking Identifier Collision Macro Tests")
struct TrackingIdentifierCollisionMacroTests {
    let testMacros: [String: Macro.Type] = [
        "Mockable": MockableMacro.self
    ]

    @Test("An overload and a method of its suffixed name get distinct members")
    func overloadAndMethodOfThatName() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Service {
                func load()
                func load(_ item: Item)
                func loadItem()
            }
            """,
            expandedSource: """
            protocol Service {
                func load()
                func load(_ item: Item)
                func loadItem()
            }

            #if DEBUG
            class ServiceMock: Service {
                var loadCallCount: Int = 0
                var loadCallArguments: [()] = []
                var loadHandler: (@Sendable () -> Void)? = nil
                func load() {
                    loadCallCount += 1
                    loadCallArguments.append(())
                    if let _handler = loadHandler {
                        _handler()
                    }
                }
                var loadItem2CallCount: Int = 0
                var loadItem2CallArguments: [Item] = []
                var loadItem2Handler: (@Sendable (Item) -> Void)? = nil
                func load(_ item: Item) {
                    loadItem2CallCount += 1
                    loadItem2CallArguments.append(item)
                    if let _handler = loadItem2Handler {
                        _handler(item)
                    }
                }
                var loadItemCallCount: Int = 0
                var loadItemCallArguments: [()] = []
                var loadItemHandler: (@Sendable () -> Void)? = nil
                func loadItem() {
                    loadItemCallCount += 1
                    loadItemCallArguments.append(())
                    if let _handler = loadItemHandler {
                        _handler()
                    }
                }
                func resetMock() {
                    loadCallCount = 0
                    loadCallArguments = []
                    loadHandler = nil
                    loadItem2CallCount = 0
                    loadItem2CallArguments = []
                    loadItem2Handler = nil
                    loadItemCallCount = 0
                    loadItemCallArguments = []
                    loadItemHandler = nil
                }
                class func resetMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("A Sendable mock's storage and reset agree on the reassigned identifier")
    func sendableStorageUsesReassignedIdentifier() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Service: Sendable {
                func load(_ item: Item)
                func load()
                func loadItem()
            }
            """,
            expandedSource: """
            protocol Service: Sendable {
                func load(_ item: Item)
                func load()
                func loadItem()
            }

            #if DEBUG
            class ServiceMock: Service, @unchecked Sendable {
                private struct Storage {
                    var loadItem2CallCount: Int = 0
                    var loadItem2CallArguments: [Item] = []
                    var loadItem2Handler: (@Sendable (Item) -> Void)? = nil
                    var loadCallCount: Int = 0
                    var loadCallArguments: [()] = []
                    var loadHandler: (@Sendable () -> Void)? = nil
                    var loadItemCallCount: Int = 0
                    var loadItemCallArguments: [()] = []
                    var loadItemHandler: (@Sendable () -> Void)? = nil
                }
                private let _storage = MockableLock<Storage>(Storage())
                var loadItem2CallCount: Int {
                    get {
                        _storage.withLock {
                            $0.loadItem2CallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.loadItem2CallCount = newValue
                        }
                    }
                }
                var loadItem2CallArguments: [Item] {
                    get {
                        _storage.withLock {
                            $0.loadItem2CallArguments
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.loadItem2CallArguments = newValue
                        }
                    }
                }
                var loadItem2Handler: (@Sendable (Item) -> Void)? {
                    get {
                        _storage.withLock {
                            $0.loadItem2Handler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.loadItem2Handler = newValue
                        }
                    }
                }
                func load(_ item: Item) {
                    let _handler = _storage.withLock { storage -> (@Sendable (Item) -> Void)? in
                        storage.loadItem2CallCount += 1
                        storage.loadItem2CallArguments.append(item)
                        return storage.loadItem2Handler
                    }
                    if let _handler {
                        _handler(item)
                    }
                }
                var loadCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.loadCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.loadCallCount = newValue
                        }
                    }
                }
                var loadCallArguments: [()] {
                    get {
                        _storage.withLock {
                            $0.loadCallArguments
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.loadCallArguments = newValue
                        }
                    }
                }
                var loadHandler: (@Sendable () -> Void)? {
                    get {
                        _storage.withLock {
                            $0.loadHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.loadHandler = newValue
                        }
                    }
                }
                func load() {
                    let _handler = _storage.withLock { storage -> (@Sendable () -> Void)? in
                        storage.loadCallCount += 1
                        storage.loadCallArguments.append(())
                        return storage.loadHandler
                    }
                    if let _handler {
                        _handler()
                    }
                }
                var loadItemCallCount: Int {
                    get {
                        _storage.withLock {
                            $0.loadItemCallCount
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.loadItemCallCount = newValue
                        }
                    }
                }
                var loadItemCallArguments: [()] {
                    get {
                        _storage.withLock {
                            $0.loadItemCallArguments
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.loadItemCallArguments = newValue
                        }
                    }
                }
                var loadItemHandler: (@Sendable () -> Void)? {
                    get {
                        _storage.withLock {
                            $0.loadItemHandler
                        }
                    }
                    set {
                        _storage.withLock {
                            $0.loadItemHandler = newValue
                        }
                    }
                }
                func loadItem() {
                    let _handler = _storage.withLock { storage -> (@Sendable () -> Void)? in
                        storage.loadItemCallCount += 1
                        storage.loadItemCallArguments.append(())
                        return storage.loadItemHandler
                    }
                    if let _handler {
                        _handler()
                    }
                }
                func resetMock() {
                    _storage.withLock { storage in
                        storage.loadItem2CallCount = 0
                        storage.loadItem2CallArguments = []
                        storage.loadItem2Handler = nil
                        storage.loadCallCount = 0
                        storage.loadCallArguments = []
                        storage.loadHandler = nil
                        storage.loadItemCallCount = 0
                        storage.loadItemCallArguments = []
                        storage.loadItemHandler = nil
                    }
                }
                class func resetMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("A subscript gives way to a method named after its identifier")
    func subscriptAndMethodOfThatName() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            protocol Service {
                func subscriptString()
                subscript(key: String) -> Int { get }
            }
            """,
            expandedSource: """
            protocol Service {
                func subscriptString()
                subscript(key: String) -> Int { get }
            }

            #if DEBUG
            class ServiceMock: Service {
                var subscriptStringCallCount: Int = 0
                var subscriptStringCallArguments: [()] = []
                var subscriptStringHandler: (@Sendable () -> Void)? = nil
                func subscriptString() {
                    subscriptStringCallCount += 1
                    subscriptStringCallArguments.append(())
                    if let _handler = subscriptStringHandler {
                        _handler()
                    }
                }
                var subscriptString2CallCount: Int = 0
                var subscriptString2CallArguments: [String] = []
                var subscriptString2Handler: (@Sendable (String) -> Int )? = nil
                subscript(key: String) -> Int {
                    subscriptString2CallCount += 1
                    subscriptString2CallArguments.append(key)
                    guard let _handler = subscriptString2Handler else {
                        fatalError("\\(Self.self).subscriptString2Handler is not set")
                    }
                    return _handler(key)
                }
                func resetMock() {
                    subscriptStringCallCount = 0
                    subscriptStringCallArguments = []
                    subscriptStringHandler = nil
                    subscriptString2CallCount = 0
                    subscriptString2CallArguments = []
                    subscriptString2Handler = nil
                }
                class func resetMock() {
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }
}
