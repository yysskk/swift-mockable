import Foundation
import Testing

import Mockable

@Suite("ResetMock Integration Tests")
struct ResetMockIntegrationTests {
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
