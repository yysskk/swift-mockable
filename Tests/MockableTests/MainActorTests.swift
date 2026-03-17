import Foundation
import Testing

import Mockable

@Suite("MainActor Integration Tests")
struct MainActorIntegrationTests {
    @Test("MainActor mock can be instantiated")
    @MainActor
    func mockCanBeInstantiated() {
        let mock = MainActorPresenterMock()
        #expect(mock.loadDataCallCount == 0)
        #expect(mock.fetchItemsCallCount == 0)
    }

    @Test("MainActor mock void method tracking")
    @MainActor
    func voidMethodTracking() {
        let mock = MainActorPresenterMock()

        mock.loadData()
        mock.loadData()

        #expect(mock.loadDataCallCount == 2)
        #expect(mock.loadDataCallArgs.count == 2)
    }

    @Test("MainActor mock void method handler is called")
    @MainActor
    func voidMethodHandler() {
        let mock = MainActorPresenterMock()
        nonisolated(unsafe) var handlerCalled = false

        mock.loadDataHandler = { @Sendable in
            handlerCalled = true
        }

        mock.loadData()

        #expect(handlerCalled)
        #expect(mock.loadDataCallCount == 1)
    }

    @Test("MainActor mock async throws method with handler")
    @MainActor
    func asyncThrowsMethod() async throws {
        let mock = MainActorPresenterMock()

        mock.fetchItemsHandler = { @Sendable in
            ["item1", "item2"]
        }

        let result = try await mock.fetchItems()

        #expect(result == ["item1", "item2"])
        #expect(mock.fetchItemsCallCount == 1)
    }

    @Test("MainActor mock async throws method can throw")
    @MainActor
    func asyncThrowsMethodThrows() async {
        let mock = MainActorPresenterMock()

        mock.fetchItemsHandler = { @Sendable in
            throw TestError.somethingWentWrong
        }

        await #expect(throws: TestError.somethingWentWrong) {
            try await mock.fetchItems()
        }
    }

    @Test("MainActor mock get-only property")
    @MainActor
    func getOnlyProperty() {
        let mock = MainActorPresenterMock()
        mock._title = "Hello"

        #expect(mock.title == "Hello")
    }

    @Test("MainActor mock get-set property")
    @MainActor
    func getSetProperty() {
        let mock = MainActorPresenterMock()
        mock.subtitle = "Sub"

        #expect(mock.subtitle == "Sub")

        mock.subtitle = "Updated"
        #expect(mock.subtitle == "Updated")
    }

    @Test("MainActor mock optional property")
    @MainActor
    func optionalProperty() {
        let mock = MainActorPresenterMock()

        #expect(mock.optionalNote == nil)

        mock.optionalNote = "Note"
        #expect(mock.optionalNote == "Note")

        mock.optionalNote = nil
        #expect(mock.optionalNote == nil)
    }

    @Test("MainActor mock conforms to protocol")
    @MainActor
    func mockConformsToProtocol() {
        @MainActor
        func usePresenter(_ presenter: MainActorPresenter) {
            presenter.loadData()
        }

        let mock = MainActorPresenterMock()
        mock.loadDataHandler = { }

        usePresenter(mock)

        #expect(mock.loadDataCallCount == 1)
    }

    @Test("MainActor mock resetMock resets all state")
    @MainActor
    func resetMock() {
        let mock = MainActorPresenterMock()
        mock.loadDataHandler = { }
        mock._title = "Title"
        mock.subtitle = "Sub"
        mock.optionalNote = "Note"

        mock.loadData()
        #expect(mock.loadDataCallCount == 1)

        mock.resetMock()

        #expect(mock.loadDataCallCount == 0)
        #expect(mock.loadDataCallArgs.isEmpty)
        #expect(mock.loadDataHandler == nil)
        #expect(mock.fetchItemsCallCount == 0)
        #expect(mock.fetchItemsCallArgs.isEmpty)
        #expect(mock.fetchItemsHandler == nil)
        #expect(mock._title == nil)
        #expect(mock._subtitle == nil)
        #expect(mock.optionalNote == nil)
    }
}
