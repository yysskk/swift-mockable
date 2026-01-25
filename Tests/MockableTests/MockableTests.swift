import Foundation
import Testing

import Mockable

// MARK: - Test Protocols

@Mockable
protocol SimpleService {
    func doSomething()
    func getValue() -> String
}

@Mockable
protocol AsyncService {
    func fetchData(id: Int) async throws -> String
}

@Mockable
protocol ServiceWithProperties {
    var readOnlyValue: Int { get }
    var readWriteValue: String { get set }
    var optionalValue: Double? { get set }
}

@Mockable
protocol MultiParameterService {
    func calculate(a: Int, b: Int, c: Int) -> Int
}

@Mockable
protocol GenericService {
    func get<T>(_ key: String) -> T
    func set<T>(_ value: T, forKey key: String)
}

@Mockable
protocol EventHandlerService {
    func subscribe(eventHandler: @escaping (String) -> Void)
    func onEvent(callback: @escaping @Sendable (Int) -> Void)
}

@Mockable
protocol SendableEventService: Sendable {
    func register(eventCallback: @escaping @Sendable (String) -> Void) async
}

// MARK: - Integration Tests

@Suite("Mockable Integration Tests")
struct MockableIntegrationTests {
    @Test("Mock can be instantiated")
    func mockCanBeInstantiated() {
        let mock = SimpleServiceMock()
        #expect(mock.doSomethingCallCount == 0)
        #expect(mock.getValueCallCount == 0)
    }

    @Test("Void method can be called and tracked")
    func voidMethodTracking() {
        let mock = SimpleServiceMock()

        mock.doSomething()
        mock.doSomething()

        #expect(mock.doSomethingCallCount == 2)
    }

    @Test("Void method handler is called when set")
    func voidMethodHandler() {
        let mock = SimpleServiceMock()
        nonisolated(unsafe) var handlerCalled = false

        mock.doSomethingHandler = {
            handlerCalled = true
        }

        mock.doSomething()

        #expect(handlerCalled)
    }

    @Test("Return value method with handler")
    func returnValueMethod() {
        let mock = SimpleServiceMock()

        mock.getValueHandler = { "test value" }

        let result = mock.getValue()

        #expect(result == "test value")
        #expect(mock.getValueCallCount == 1)
    }

    @Test("Async throws method with handler")
    func asyncThrowsMethod() async throws {
        let mock = AsyncServiceMock()

        mock.fetchDataHandler = { @Sendable id in
            "data for \(id)"
        }

        let result = try await mock.fetchData(id: 42)

        #expect(result == "data for 42")
        #expect(mock.fetchDataCallCount == 1)
        #expect(mock.fetchDataCallArgs == [42])
    }

    @Test("Async throws method can throw")
    func asyncThrowsMethodThrows() async {
        let mock = AsyncServiceMock()

        mock.fetchDataHandler = { @Sendable _ in
            throw TestError.somethingWentWrong
        }

        await #expect(throws: TestError.somethingWentWrong) {
            try await mock.fetchData(id: 1)
        }
    }

    @Test("Get-only property")
    func getOnlyProperty() {
        let mock = ServiceWithPropertiesMock()
        mock._readOnlyValue = 42

        #expect(mock.readOnlyValue == 42)
    }

    @Test("Get-set property")
    func getSetProperty() {
        let mock = ServiceWithPropertiesMock()
        mock.readWriteValue = "hello"

        #expect(mock.readWriteValue == "hello")

        mock.readWriteValue = "world"
        #expect(mock.readWriteValue == "world")
    }

    @Test("Optional property")
    func optionalProperty() {
        let mock = ServiceWithPropertiesMock()

        #expect(mock.optionalValue == nil)

        mock.optionalValue = 3.14
        #expect(mock.optionalValue == 3.14)

        mock.optionalValue = nil
        #expect(mock.optionalValue == nil)
    }

    @Test("Multiple parameters are tracked")
    func multipleParameters() {
        let mock = MultiParameterServiceMock()

        mock.calculateHandler = { @Sendable args in
            args.a + args.b + args.c
        }

        let result = mock.calculate(a: 1, b: 2, c: 3)

        #expect(result == 6)
        #expect(mock.calculateCallCount == 1)
        #expect(mock.calculateCallArgs.count == 1)
        #expect(mock.calculateCallArgs[0].a == 1)
        #expect(mock.calculateCallArgs[0].b == 2)
        #expect(mock.calculateCallArgs[0].c == 3)
    }

    @Test("Generic method with return")
    func genericMethodWithReturn() {
        let mock = GenericServiceMock()

        mock.getHandler = { @Sendable key in
            if key == "number" {
                return 42
            } else {
                return "default"
            }
        }

        let number: Int = mock.get("number")
        let string: String = mock.get("string")

        #expect(number == 42)
        #expect(string == "default")
        #expect(mock.getCallCount == 2)
        #expect(mock.getCallArgs == ["number", "string"])
    }

    @Test("Generic method with generic parameter")
    func genericMethodWithGenericParameter() {
        let mock = GenericServiceMock()

        mock.setHandler = { @Sendable _ in }

        mock.set(42, forKey: "number")
        mock.set("hello", forKey: "greeting")

        #expect(mock.setCallCount == 2)
        #expect(mock.setCallArgs.count == 2)
        #expect(mock.setCallArgs[0].key == "number")
        #expect(mock.setCallArgs[0].value as? Int == 42)
        #expect(mock.setCallArgs[1].key == "greeting")
        #expect(mock.setCallArgs[1].value as? String == "hello")
    }

    @Test("Mock conforms to protocol")
    func mockConformsToProtocol() {
        func useService(_ service: SimpleService) -> String {
            service.getValue()
        }

        let mock = SimpleServiceMock()
        mock.getValueHandler = { "from mock" }

        let result = useService(mock)

        #expect(result == "from mock")
    }

    @Test("Method with @escaping closure parameter")
    func escapingClosureParameter() {
        let mock = EventHandlerServiceMock()
        nonisolated(unsafe) var receivedValue: String?

        mock.subscribeHandler = { @Sendable eventHandler in
            eventHandler("test event")
        }

        mock.subscribe { value in
            receivedValue = value
        }

        #expect(mock.subscribeCallCount == 1)
        #expect(receivedValue == "test event")
    }

    @Test("Method with @escaping @Sendable closure parameter")
    func escapingSendableClosureParameter() {
        let mock = EventHandlerServiceMock()
        nonisolated(unsafe) var receivedValue: Int?

        mock.onEventHandler = { @Sendable callback in
            callback(42)
        }

        mock.onEvent { value in
            receivedValue = value
        }

        #expect(mock.onEventCallCount == 1)
        #expect(receivedValue == 42)
    }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
    @Test("Sendable protocol with @escaping @Sendable closure parameter")
    func sendableProtocolEscapingClosure() async {
        let mock = SendableEventServiceMock()
        nonisolated(unsafe) var receivedValue: String?

        mock.registerHandler = { @Sendable eventCallback in
            eventCallback("registered")
        }

        await mock.register { value in
            receivedValue = value
        }

        #expect(mock.registerCallCount == 1)
        #expect(receivedValue == "registered")
    }

    // MARK: - resetMock Tests

    @Test("resetMock resets call count and call args for methods")
    func resetMockResetsMethodTracking() {
        let mock = SimpleServiceMock()
        mock.getValueHandler = { "value" }

        // Call methods multiple times
        mock.doSomething()
        mock.doSomething()
        _ = mock.getValue()

        #expect(mock.doSomethingCallCount == 2)
        #expect(mock.getValueCallCount == 1)

        // Reset the mock
        mock.resetMock()

        // Verify all counts and args are reset
        #expect(mock.doSomethingCallCount == 0)
        #expect(mock.doSomethingCallArgs.isEmpty)
        #expect(mock.doSomethingHandler == nil)
        #expect(mock.getValueCallCount == 0)
        #expect(mock.getValueCallArgs.isEmpty)
        #expect(mock.getValueHandler == nil)
    }

    @Test("resetMock resets handlers to nil")
    func resetMockResetsHandlers() {
        let mock = SimpleServiceMock()
        mock.doSomethingHandler = {}
        mock.getValueHandler = { "value" }

        #expect(mock.doSomethingHandler != nil)
        #expect(mock.getValueHandler != nil)

        mock.resetMock()

        #expect(mock.doSomethingHandler == nil)
        #expect(mock.getValueHandler == nil)
    }

    @Test("resetMock resets properties")
    func resetMockResetsProperties() {
        let mock = ServiceWithPropertiesMock()
        mock._readOnlyValue = 42
        mock._readWriteValue = "hello"
        mock.optionalValue = 3.14

        mock.resetMock()

        #expect(mock._readOnlyValue == nil)
        #expect(mock._readWriteValue == nil)
        #expect(mock.optionalValue == nil)
    }

    @Test("resetMock resets call args for methods with parameters")
    func resetMockResetsCallArgs() {
        let mock = MultiParameterServiceMock()
        mock.calculateHandler = { @Sendable args in args.a + args.b + args.c }

        _ = mock.calculate(a: 1, b: 2, c: 3)
        _ = mock.calculate(a: 4, b: 5, c: 6)

        #expect(mock.calculateCallCount == 2)
        #expect(mock.calculateCallArgs.count == 2)

        mock.resetMock()

        #expect(mock.calculateCallCount == 0)
        #expect(mock.calculateCallArgs.isEmpty)
        #expect(mock.calculateHandler == nil)
    }

    @Test("resetMock allows mock to be reused")
    func resetMockAllowsReuse() {
        let mock = SimpleServiceMock()
        mock.getValueHandler = { "first" }

        let firstResult = mock.getValue()
        #expect(firstResult == "first")
        #expect(mock.getValueCallCount == 1)

        mock.resetMock()

        // Set new handler after reset
        mock.getValueHandler = { "second" }

        let secondResult = mock.getValue()
        #expect(secondResult == "second")
        #expect(mock.getValueCallCount == 1)
    }

    @Test("resetMock resets async service mock")
    func resetMockResetsAsyncService() async throws {
        let mock = AsyncServiceMock()
        mock.fetchDataHandler = { @Sendable id in "data \(id)" }

        _ = try await mock.fetchData(id: 1)
        _ = try await mock.fetchData(id: 2)

        #expect(mock.fetchDataCallCount == 2)
        #expect(mock.fetchDataCallArgs == [1, 2])

        mock.resetMock()

        #expect(mock.fetchDataCallCount == 0)
        #expect(mock.fetchDataCallArgs == [])
        #expect(mock.fetchDataHandler == nil)
    }

    @Test("resetMock resets generic service mock")
    func resetMockResetsGenericService() {
        let mock = GenericServiceMock()
        mock.getHandler = { @Sendable _ in 42 }
        mock.setHandler = { @Sendable _ in }

        let _: Int = mock.get("key")
        mock.set("value", forKey: "key")

        #expect(mock.getCallCount == 1)
        #expect(mock.setCallCount == 1)

        mock.resetMock()

        #expect(mock.getCallCount == 0)
        #expect(mock.getCallArgs == [])
        #expect(mock.getHandler == nil)
        #expect(mock.setCallCount == 0)
        #expect(mock.setCallArgs.isEmpty)
        #expect(mock.setHandler == nil)
    }
}

// MARK: - Helpers

enum TestError: Error, Equatable {
    case somethingWentWrong
}
