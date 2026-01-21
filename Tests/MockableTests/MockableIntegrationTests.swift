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

        mock.doSomethingHandler = { @Sendable (_: ()) -> Void in
            handlerCalled = true
        }

        mock.doSomething()

        #expect(handlerCalled)
    }

    @Test("Return value method with handler")
    func returnValueMethod() {
        let mock = SimpleServiceMock()

        mock.getValueHandler = { @Sendable (_: ()) -> String in
            "test value"
        }

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
        mock.getValueHandler = { @Sendable (_: ()) -> String in "from mock" }

        let result = useService(mock)

        #expect(result == "from mock")
    }
}

// MARK: - Helpers

enum TestError: Error, Equatable {
    case somethingWentWrong
}
