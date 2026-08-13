import Testing

import Mockable

// A `nonisolated` requirement of a global-actor-isolated protocol. Swift infers the
// isolation of a witness from the requirement it satisfies, so the witness is
// nonisolated and cannot read isolated stored properties — compiling this mock is most
// of the test.

@MainActor
@Mockable
protocol NonisolatedPresenter {
    nonisolated var id: String { get }
    nonisolated func track(_ event: String)
    func loadData() -> Int
}

@Suite("Nonisolated Member Integration Tests")
struct NonisolatedMemberTests {
    @Test("A nonisolated requirement is usable without hopping to the main actor")
    func nonisolatedMembersAreReachable() {
        // The mock's initializer is nonisolated, so this test never touches the actor.
        let mock = NonisolatedPresenterMock()

        // Set up and read the tracking state from a nonisolated context.
        mock._id = "mock-id"
        mock.trackHandler = { _ in }

        #expect(mock.id == "mock-id")
        mock.track("opened")

        #expect(mock.trackCallCount == 1)
        #expect(mock.trackCallArgs == ["opened"])
    }

    @Test("An isolated requirement of the same protocol still works")
    @MainActor
    func isolatedMembersStillWork() {
        let mock = NonisolatedPresenterMock()
        mock.loadDataHandler = { 7 }

        #expect(mock.loadData() == 7)
        #expect(mock.loadDataCallCount == 1)

        mock.resetMock()
        #expect(mock.loadDataCallCount == 0)
        #expect(mock.trackCallCount == 0)
    }
}
