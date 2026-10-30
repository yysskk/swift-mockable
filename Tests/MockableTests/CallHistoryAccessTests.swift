import Testing

import Mockable

// The call history a mock records — `<name>CallCount` and `<name>CallArguments` — is
// read-only from outside the mock (`private(set)` on a plain mock, get-only on a
// lock-backed one), so only the witness and `resetMock()` write it. These tests check
// that both still can, for each storage model.

// Used by one test only: its static state is shared by every instance.
@Mockable
protocol HeartbeatService {
    static func ping()
    func beat(at time: Int)
}

@Suite("Call History Access Integration Tests")
struct CallHistoryAccessTests {
    @Test("A plain mock records into and resets its read-only call history")
    func plainMock() {
        let mock = SimpleServiceMock()
        mock.getValueHandler = { "value" }

        _ = mock.getValue()
        _ = mock.getValue()

        #expect(mock.getValueCallCount == 2)

        mock.resetMock()

        #expect(mock.getValueCallCount == 0)
    }

    @Test("A Sendable mock records into and resets its read-only call history")
    func sendableMock() async {
        let mock = SendableEventServiceMock()

        await mock.register { _ in }

        #expect(mock.registerCallCount == 1)
        #expect(mock.registerCallArguments.count == 1)

        mock.resetMock()

        #expect(mock.registerCallCount == 0)
        #expect(mock.registerCallArguments.isEmpty)
    }

    @Test("An actor mock records into and resets its read-only call history")
    func actorMock() async {
        let mock = UserProfileStoreMock()

        await mock.updateProfile("Alice", for: "alice")

        #expect(mock.updateProfileCallCount == 1)
        #expect(mock.updateProfileCallArguments.first?.key == "alice")

        mock.resetMock()

        #expect(mock.updateProfileCallCount == 0)
        #expect(mock.updateProfileCallArguments.isEmpty)
    }

    @Test("A requirement without arguments records its calls in the call count alone")
    func requirementWithoutArguments() {
        HeartbeatServiceMock.resetStaticMock()
        let mock = HeartbeatServiceMock()

        HeartbeatServiceMock.ping()
        HeartbeatServiceMock.ping()
        mock.beat(at: 3)

        #expect(HeartbeatServiceMock.pingCallCount == 2)
        #expect(mock.beatCallArguments == [3])

        HeartbeatServiceMock.resetStaticMock()

        #expect(HeartbeatServiceMock.pingCallCount == 0)
    }
}
