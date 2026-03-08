import Foundation
import Testing

import Mockable

// MARK: - Test Protocols

@Mockable
protocol SendableService: Sendable {
    func performTask(id: Int) async throws -> String
    func log(message: String)
}

@Mockable
protocol SendableConfigProvider: Sendable {
    var apiKey: String { get }
    var timeout: Int { get set }
    var optionalEndpoint: String? { get set }
}

@Mockable
protocol SendableVariadicService: Sendable {
    func log(_ messages: String...)
}

@Mockable
protocol SendableStaticService: Sendable {
    static func lookup(key: String) -> String
    static var sharedToken: String? { get set }
}

@Mockable
protocol SendableInoutService: Sendable {
    func sort(_ array: inout [Int])
}

@Mockable
protocol SendableInoutWithReturnService: Sendable {
    func removeFirst(_ array: inout [String]) -> String
}

@Mockable
protocol SendableMultipleInoutService: Sendable {
    func swap(_ a: inout Int, _ b: inout Int)
}

@Mockable
protocol SendableInoutThrowsService: Sendable {
    func parse(_ buffer: inout [UInt8]) throws -> String
}

// MARK: - Sendable Integration Tests

@Suite("Sendable Integration Tests")
struct SendableIntegrationTests {
    @Test("Sendable mock can be instantiated")
    func sendableMockCanBeInstantiated() {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = SendableServiceMock()
        #expect(mock.performTaskCallCount == 0)
        #expect(mock.logCallCount == 0)
    }

    @Test("Sendable mock is Sendable")
    func sendableMockIsSendable() {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = SendableServiceMock()
        mock.logHandler = { @Sendable _ in }

        // Verify the mock conforms to Sendable by using it in a context requiring Sendable
        func useSendable<T: Sendable>(_ value: T) -> T { value }
        let result = useSendable(mock)
        #expect(result === mock)
    }

    @Test("Sendable mock conforms to protocol")
    func sendableMockConformsToProtocol() {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        func useService(_ service: SendableService) {
            service.log(message: "test")
        }

        let mock = SendableServiceMock()
        mock.logHandler = { @Sendable _ in }

        useService(mock)

        #expect(mock.logCallCount == 1)
        #expect(mock.logCallArgs == ["test"])
    }

    @Test("Sendable mock async method works")
    func sendableMockAsyncMethod() async throws {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = SendableServiceMock()

        mock.performTaskHandler = { @Sendable id in
            "result for \(id)"
        }

        let result = try await mock.performTask(id: 123)

        #expect(result == "result for 123")
        #expect(mock.performTaskCallCount == 1)
        #expect(mock.performTaskCallArgs == [123])
    }

    @Test("Sendable mock void method tracking")
    func sendableMockVoidMethodTracking() {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = SendableServiceMock()
        mock.logHandler = { @Sendable _ in }

        mock.log(message: "first")
        mock.log(message: "second")
        mock.log(message: "third")

        #expect(mock.logCallCount == 3)
        #expect(mock.logCallArgs == ["first", "second", "third"])
    }

    @Test("Sendable static members are tracked and reset")
    func sendableStaticMembers() {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let resetter = SendableStaticServiceMock()
        resetter.resetMock()

        SendableStaticServiceMock.lookupHandler = { @Sendable key in
            "value-\(key)"
        }
        SendableStaticServiceMock.sharedToken = "token"

        let result = SendableStaticServiceMock.lookup(key: "abc")

        #expect(result == "value-abc")
        #expect(SendableStaticServiceMock.lookupCallCount == 1)
        #expect(SendableStaticServiceMock.lookupCallArgs == ["abc"])
        #expect(SendableStaticServiceMock.sharedToken == "token")

        resetter.resetMock()
        #expect(SendableStaticServiceMock.lookupCallCount == 0)
        #expect(SendableStaticServiceMock.lookupCallArgs == [])
        #expect(SendableStaticServiceMock.lookupHandler == nil)
        #expect(SendableStaticServiceMock.sharedToken == nil)
    }

    @Test("Sendable mock inout parameter is tracked and write-backed")
    func sendableMockInoutWriteBack() {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = SendableInoutServiceMock()
        mock.sortHandler = { @Sendable values in
            values.sorted()
        }

        var values = [9, 4, 1]
        mock.sort(&values)

        #expect(mock.sortCallCount == 1)
        #expect(mock.sortCallArgs == [[9, 4, 1]])
        #expect(values == [1, 4, 9])
    }

    @Test("Sendable mock inout with return value")
    func sendableMockInoutWithReturnValue() {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = SendableInoutWithReturnServiceMock()
        mock.removeFirstHandler = { @Sendable array in
            let first = array.first!
            return (returnValue: first, inoutArgs: Array(array.dropFirst()))
        }

        var items = ["x", "y", "z"]
        let removed = mock.removeFirst(&items)

        #expect(removed == "x")
        #expect(items == ["y", "z"])
        #expect(mock.removeFirstCallCount == 1)
        #expect(mock.removeFirstCallArgs == [["x", "y", "z"]])
    }

    @Test("Sendable mock multiple inout parameters")
    func sendableMockMultipleInoutParameters() {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = SendableMultipleInoutServiceMock()
        mock.swapHandler = { @Sendable args in
            (a: args.1, b: args.0)
        }

        var x = 100
        var y = 200
        mock.swap(&x, &y)

        #expect(x == 200)
        #expect(y == 100)
        #expect(mock.swapCallCount == 1)
    }

    @Test("Sendable mock inout with throws")
    func sendableMockInoutWithThrows() throws {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = SendableInoutThrowsServiceMock()
        mock.parseHandler = { @Sendable buffer in
            let str = String(bytes: buffer, encoding: .utf8)!
            return (returnValue: str, inoutArgs: [])
        }

        var buffer: [UInt8] = Array("test".utf8)
        let result = try mock.parse(&buffer)

        #expect(result == "test")
        #expect(buffer == [])
        #expect(mock.parseCallCount == 1)
    }

    @Test("Sendable variadic method tracks arrays and handler receives array")
    func sendableVariadicMethod() {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = SendableVariadicServiceMock()
        nonisolated(unsafe) var captured: [String] = []

        mock.logHandler = { @Sendable messages in
            captured = messages
        }

        mock.log("first", "second")

        #expect(mock.logCallCount == 1)
        #expect(mock.logCallArgs == [["first", "second"]])
        #expect(captured == ["first", "second"])
    }

    @Test("Sendable mock can be used from multiple tasks")
    func sendableMockConcurrentAccess() async {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = SendableServiceMock()
        mock.logHandler = { @Sendable _ in }

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    mock.log(message: "message \(i)")
                }
            }
        }

        #expect(mock.logCallCount == 100)
        #expect(mock.logCallArgs.count == 100)
    }

    @Test("Sendable config provider mock get-only property")
    func sendableConfigProviderGetOnlyProperty() {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = SendableConfigProviderMock()
        mock._apiKey = "secret-key"

        #expect(mock.apiKey == "secret-key")
    }

    @Test("Sendable config provider mock get-set property")
    func sendableConfigProviderGetSetProperty() {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = SendableConfigProviderMock()
        mock.timeout = 30

        #expect(mock.timeout == 30)

        mock.timeout = 60
        #expect(mock.timeout == 60)
    }

    @Test("Sendable config provider mock optional property")
    func sendableConfigProviderOptionalProperty() {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = SendableConfigProviderMock()

        #expect(mock.optionalEndpoint == nil)

        mock.optionalEndpoint = "https://api.example.com"
        #expect(mock.optionalEndpoint == "https://api.example.com")

        mock.optionalEndpoint = nil
        #expect(mock.optionalEndpoint == nil)
    }

    @Test("Sendable config provider is Sendable")
    func sendableConfigProviderIsSendable() {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = SendableConfigProviderMock()
        mock._apiKey = "test"
        mock.timeout = 10

        // Verify the mock conforms to Sendable
        func useSendable<T: Sendable>(_ value: T) -> T { value }
        let result = useSendable(mock)
        #expect(result === mock)
    }

    @Test("Sendable config provider concurrent property access")
    func sendableConfigProviderConcurrentAccess() async {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = SendableConfigProviderMock()
        mock._apiKey = "initial"
        mock.timeout = 0

        await withTaskGroup(of: Void.self) { group in
            // Multiple reads
            for _ in 0..<50 {
                group.addTask {
                    _ = mock.apiKey
                    _ = mock.timeout
                }
            }
            // Multiple writes
            for i in 0..<50 {
                group.addTask {
                    mock.timeout = i
                }
            }
        }

        // Just verify no crashes occurred and we can still access properties
        #expect(mock.apiKey == "initial")
        #expect(mock.timeout >= 0 && mock.timeout < 50)
    }

    // MARK: - resetMock Tests for Sendable Mocks

    @Test("Sendable mock resetMock resets call count and args")
    func sendableMockResetMockResetsMethodTracking() {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = SendableServiceMock()
        mock.logHandler = { @Sendable _ in }

        mock.log(message: "first")
        mock.log(message: "second")

        #expect(mock.logCallCount == 2)
        #expect(mock.logCallArgs == ["first", "second"])

        mock.resetMock()

        #expect(mock.logCallCount == 0)
        #expect(mock.logCallArgs == [])
        #expect(mock.logHandler == nil)
    }

    @Test("Sendable mock resetMock resets async method tracking")
    func sendableMockResetMockResetsAsyncMethod() async throws {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = SendableServiceMock()
        mock.performTaskHandler = { @Sendable id in "result \(id)" }

        _ = try await mock.performTask(id: 1)
        _ = try await mock.performTask(id: 2)

        #expect(mock.performTaskCallCount == 2)
        #expect(mock.performTaskCallArgs == [1, 2])

        mock.resetMock()

        #expect(mock.performTaskCallCount == 0)
        #expect(mock.performTaskCallArgs == [])
        #expect(mock.performTaskHandler == nil)
    }

    @Test("Sendable mock resetMock resets all handlers")
    func sendableMockResetMockResetsHandlers() {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = SendableServiceMock()
        mock.performTaskHandler = { @Sendable _ in "result" }
        mock.logHandler = { @Sendable _ in }

        #expect(mock.performTaskHandler != nil)
        #expect(mock.logHandler != nil)

        mock.resetMock()

        #expect(mock.performTaskHandler == nil)
        #expect(mock.logHandler == nil)
    }

    @Test("Sendable config provider resetMock resets properties")
    func sendableConfigProviderResetMockResetsProperties() {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = SendableConfigProviderMock()
        mock._apiKey = "secret"
        mock.timeout = 30
        mock.optionalEndpoint = "https://example.com"

        mock.resetMock()

        #expect(mock._apiKey == nil)
        // timeout's backing storage is reset inside _storage (not externally accessible)
        #expect(mock.optionalEndpoint == nil)
    }

    @Test("Sendable mock resetMock allows reuse")
    func sendableMockResetMockAllowsReuse() {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = SendableServiceMock()
        mock.logHandler = { @Sendable _ in }

        mock.log(message: "first session")
        #expect(mock.logCallCount == 1)

        mock.resetMock()

        mock.logHandler = { @Sendable _ in }
        mock.log(message: "second session")
        mock.log(message: "second session again")

        #expect(mock.logCallCount == 2)
        #expect(mock.logCallArgs == ["second session", "second session again"])
    }

    @Test("Sendable mock resetMock is thread-safe")
    func sendableMockResetMockIsThreadSafe() async {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = SendableServiceMock()
        mock.logHandler = { @Sendable _ in }

        // Concurrent access with resets
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    mock.log(message: "message \(i)")
                }
            }
            for _ in 0..<10 {
                group.addTask {
                    mock.resetMock()
                }
            }
        }

        // Just verify no crashes occurred
        // The exact state is non-deterministic due to concurrent resets
        #expect(mock.logCallCount >= 0)
    }
}
