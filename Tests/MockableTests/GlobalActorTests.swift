import Testing

import Mockable

@globalActor
actor DataActor {
    static let shared = DataActor()
}

// A protocol isolated to a custom global actor. Its mock is isolated the same way, and
// a `nonisolated` requirement gets the same nonisolated, lock-backed tracking members a
// `@MainActor` protocol's does — compiling this mock is most of the test.

@DataActor
@Mockable
protocol DataStore {
    nonisolated var id: String { get }
    nonisolated static func make() -> Int
    func save(_ value: String)
}

@DataActor
@Mockable
protocol DataChildStore: BaseService {
    func refresh()
}

// A protocol that inherits its isolation from a `@MainActor` parent and declares a
// `nonisolated` requirement of its own.
@Mockable
protocol TrackingPresenter: MainActorPresenter {
    nonisolated func track(_ event: String)
}

@Suite("Global Actor Tests")
struct GlobalActorTests {
    @Test("A nonisolated requirement of a custom-actor protocol is usable from anywhere")
    func nonisolatedMembersAreReachable() {
        let mock = DataStoreMock()
        mock._id = "store"
        DataStoreMock.makeHandler = { 7 }

        #expect(mock.id == "store")
        #expect(DataStoreMock.make() == 7)
        #expect(DataStoreMock.makeCallCount == 1)

        mock.resetMock()

        #expect(mock._id == nil)
        #expect(DataStoreMock.makeCallCount == 0)
        #expect(DataStoreMock.makeHandler == nil)
    }

    @Test("An isolated requirement of a custom-actor protocol is tracked on its actor")
    @DataActor
    func isolatedMembersWork() {
        let mock = DataStoreMock()
        mock.saveHandler = { _ in }

        mock.save("value")

        #expect(mock.saveCallCount == 1)
        #expect(mock.saveCallArgs == ["value"])

        mock.resetMock()
        #expect(mock.saveCallCount == 0)
    }

    @Test("A custom-actor child of a nonisolated parent resets both sides")
    @DataActor
    func childOfNonisolatedParent() {
        let mock = DataChildStoreMock()
        mock.baseMethodHandler = { "base" }
        mock.refreshHandler = { }

        #expect(mock.baseMethod() == "base")
        mock.refresh()
        #expect(mock.refreshCallCount == 1)

        mock.resetMock()

        #expect(mock.baseMethodCallCount == 0)
        #expect(mock.refreshCallCount == 0)
        #expect(mock.refreshHandler == nil)
    }

    @Test("A nonisolated requirement of an unannotated child is usable from anywhere")
    func inheritedIsolation() {
        let mock = TrackingPresenterMock()
        mock.trackHandler = { _ in }

        mock.track("opened")

        #expect(mock.trackCallCount == 1)
        #expect(mock.trackCallArgs == ["opened"])
    }

    @Test("An unannotated child still tracks its parent's isolated requirements")
    @MainActor
    func inheritedIsolationParentMembers() {
        let mock = TrackingPresenterMock()
        mock.loadDataHandler = { }

        mock.loadData()
        #expect(mock.loadDataCallCount == 1)

        mock.resetMock()
        #expect(mock.loadDataCallCount == 0)
        #expect(mock.trackCallCount == 0)
    }
}
