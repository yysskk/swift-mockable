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
    func save(_ value: String)
}

// Static state is shared by every instance of a mock, and `resetMock()` clears it, so
// the static requirement gets a mock of its own that a single test touches.
@DataActor
@Mockable
protocol DataStoreFactory {
    nonisolated static func make() -> Int
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

        #expect(mock.id == "store")

        mock.resetMock()

        #expect(mock._id == nil)
    }

    @Test("A nonisolated static requirement of a custom-actor protocol is usable from anywhere")
    func nonisolatedStaticMembersAreReachable() {
        DataStoreFactoryMock.makeHandler = { 7 }

        #expect(DataStoreFactoryMock.make() == 7)
        #expect(DataStoreFactoryMock.makeCallCount == 1)

        DataStoreFactoryMock().resetMock()

        #expect(DataStoreFactoryMock.makeCallCount == 0)
        #expect(DataStoreFactoryMock.makeHandler == nil)
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
