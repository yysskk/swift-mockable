import Testing

import Mockable

// Static tracking state is shared by every instance, so it lives behind a lock even in a
// mock whose instance state does not, and it is cleared through the type rather than an
// instance. The type-level `resetMock()` has to clear it in one acquisition: a caller
// recording a call concurrently must never see a half-reset mock.

@Mockable
protocol StaticResetService {
    static func record(_ value: Int)
    func ping()
}

// Static tracking state belongs to the mock type, not to an instance, so these tests
// would otherwise interfere with each other's setup.
@Suite("Static Reset Integration Tests", .serialized)
struct StaticResetTests {
    @Test("Static tracking state is cleared as a whole by the type's resetMock")
    func staticStateIsCleared() {
        StaticResetServiceMock.resetMock()

        StaticResetServiceMock.recordHandler = { _ in }
        StaticResetServiceMock.record(1)
        StaticResetServiceMock.record(2)

        #expect(StaticResetServiceMock.recordCallCount == 2)
        #expect(StaticResetServiceMock.recordCallArgs == [1, 2])

        StaticResetServiceMock.resetMock()

        #expect(StaticResetServiceMock.recordCallCount == 0)
        #expect(StaticResetServiceMock.recordCallArgs.isEmpty)
        #expect(StaticResetServiceMock.recordHandler == nil)
    }

    @Test("An instance's resetMock leaves the static state alone")
    func instanceResetLeavesStaticState() {
        StaticResetServiceMock.resetMock()
        let mock = StaticResetServiceMock()

        StaticResetServiceMock.recordHandler = { _ in }
        StaticResetServiceMock.record(1)
        mock.ping()

        mock.resetMock()

        #expect(mock.pingCallCount == 0)
        #expect(StaticResetServiceMock.recordCallCount == 1)
        #expect(StaticResetServiceMock.recordHandler != nil)

        StaticResetServiceMock.resetMock()
        #expect(StaticResetServiceMock.recordCallCount == 0)
    }

    @Test("The type's resetMock leaves an instance's state alone")
    func typeResetLeavesInstanceState() {
        StaticResetServiceMock.resetMock()
        let mock = StaticResetServiceMock()

        mock.ping()
        StaticResetServiceMock.resetMock()

        #expect(mock.pingCallCount == 1)
    }

    @Test("Resetting while calls are recorded leaves the mock consistent")
    func resetUnderConcurrency() async {
        StaticResetServiceMock.resetMock()
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
                for _ in 0..<200 {
                    StaticResetServiceMock.resetMock()
                }
            }
        }

        StaticResetServiceMock.resetMock()
        #expect(StaticResetServiceMock.recordCallCount == 0)
        #expect(StaticResetServiceMock.recordCallArgs.isEmpty)
        #expect(StaticResetServiceMock.recordHandler == nil)
    }
}
