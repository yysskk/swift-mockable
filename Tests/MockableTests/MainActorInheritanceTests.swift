import Testing

import Mockable

@Suite("MainActor Inheritance Tests")
struct MainActorInheritanceTests {
    @Test("A @MainActor child of a nonisolated parent tracks and resets both sides")
    @MainActor
    func childOfNonisolatedParent() {
        let mock = MainActorChildServiceMock()
        mock.baseMethodHandler = { "base" }
        mock._baseName = "name"
        mock.refreshHandler = { }
        mock.subtitle = "sub"
        MainActorChildServiceMock.makeHandler = { 7 }

        #expect(mock.baseMethod() == "base")
        #expect(mock.baseName == "name")
        mock.refresh()
        #expect(mock.refreshCallCount == 1)
        #expect(mock.subtitle == "sub")
        #expect(MainActorChildServiceMock.make() == 7)
        #expect(MainActorChildServiceMock.makeCallCount == 1)

        mock.resetMock()

        #expect(mock.baseMethodCallCount == 0)
        #expect(mock._baseName == nil)
        #expect(mock.refreshCallCount == 0)
        #expect(mock.refreshHandler == nil)
        #expect(mock._subtitle == nil)
        #expect(MainActorChildServiceMock.makeCallCount == 0)
        #expect(MainActorChildServiceMock.makeHandler == nil)
    }

    @Test("A @MainActor child of a @MainActor parent tracks and resets both sides")
    @MainActor
    func childOfIsolatedParent() {
        let mock = MainActorChildPresenterMock()
        mock.loadDataHandler = { }
        mock.refreshHandler = { }

        mock.loadData()
        mock.refresh()
        #expect(mock.loadDataCallCount == 1)
        #expect(mock.refreshCallCount == 1)

        mock.resetMock()

        #expect(mock.loadDataCallCount == 0)
        #expect(mock.refreshCallCount == 0)
    }

    @Test("A nonisolated requirement of a child is usable without hopping to the main actor")
    func nonisolatedRequirementOfChild() {
        let mock = TrackingChildServiceMock()
        mock.trackHandler = { _ in }

        mock.track("opened")

        #expect(mock.trackCallCount == 1)
        #expect(mock.trackCallArgs == ["opened"])

        // The parent is nonisolated, so its override of `resetMock()` is too.
        mock.resetMock()

        #expect(mock.trackCallCount == 0)
        #expect(mock.trackHandler == nil)
    }

    @Test("A child mock can be used as its parent type")
    @MainActor
    func childMockAsParentType() {
        let mock = MainActorChildServiceMock()
        mock.baseMethodHandler = { "value" }

        let service: BaseService = mock
        #expect(service.baseMethod() == "value")
        #expect(mock.baseMethodCallCount == 1)
    }
}
