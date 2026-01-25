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
}
