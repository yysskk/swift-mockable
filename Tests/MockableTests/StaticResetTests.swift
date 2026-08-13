import Testing

import Mockable

// Static tracking state is shared by every instance, so it lives behind a lock even in a
// mock whose instance state does not. `resetMock()` has to clear it in one acquisition:
// a caller recording a call concurrently must never see a half-reset mock.

@Mockable
protocol StaticResetService {
    static func record(_ value: Int)
}

// Static tracking state belongs to the mock type, not to an instance, so these tests
// would otherwise interfere with each other's setup.
@Suite("Static Reset Integration Tests", .serialized)
struct StaticResetTests {
    @Test("Static tracking state is cleared as a whole")
    func staticStateIsCleared() {
        let mock = StaticResetServiceMock()
        mock.resetMock()

        StaticResetServiceMock.recordHandler = { _ in }
        StaticResetServiceMock.record(1)
        StaticResetServiceMock.record(2)

        #expect(StaticResetServiceMock.recordCallCount == 2)
        #expect(StaticResetServiceMock.recordCallArgs == [1, 2])

        mock.resetMock()

        #expect(StaticResetServiceMock.recordCallCount == 0)
        #expect(StaticResetServiceMock.recordCallArgs.isEmpty)
        #expect(StaticResetServiceMock.recordHandler == nil)
    }

    @Test("Resetting while calls are recorded leaves the mock consistent")
    func resetUnderConcurrency() async {
        let mock = StaticResetServiceMock()
        mock.resetMock()
        StaticResetServiceMock.recordHandler = { _ in }

        // Recording and resetting the same static slots from two tasks. Each reset
        // clears them in one acquisition, so it never interleaves with the recording
        // of a single call.
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for value in 0..<200 {
                    StaticResetServiceMock.record(value)
                }
            }
            group.addTask {
                // Static state belongs to the type, so this resets the very slots the
                // other task is recording into.
                let resetter = StaticResetServiceMock()
                for _ in 0..<200 {
                    resetter.resetMock()
                }
            }
        }

        mock.resetMock()
        #expect(StaticResetServiceMock.recordCallCount == 0)
        #expect(StaticResetServiceMock.recordCallArgs.isEmpty)
        #expect(StaticResetServiceMock.recordHandler == nil)
    }
}
