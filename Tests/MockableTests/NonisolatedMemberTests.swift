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

@MainActor
@Mockable
protocol NonisolatedVariety {
    nonisolated static func make() -> Int
    nonisolated subscript(key: String) -> Int { get set }
    nonisolated var token: String { get throws }
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

        // The state was set up from here, so it has to be clearable from here too.
        mock.resetMock()

        #expect(mock.trackCallCount == 0)
        #expect(mock.trackCallArgs.isEmpty)
        #expect(mock.trackHandler == nil)
    }

    @Test("A nonisolated static, subscript, and effectful property are all reachable")
    func nonisolatedRequirementKinds() throws {
        let mock = NonisolatedVarietyMock()
        mock.resetMock()

        NonisolatedVarietyMock.makeHandler = { 7 }
        mock.subscriptStringHandler = { $0.count }
        mock.tokenHandler = { "token" }

        #expect(NonisolatedVarietyMock.make() == 7)
        #expect(mock["abc"] == 3)
        #expect(try mock.token == "token")

        mock.resetMock()
        #expect(NonisolatedVarietyMock.makeCallCount == 0)
        #expect(mock.subscriptStringCallCount == 0)
        #expect(mock.tokenCallCount == 0)
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
