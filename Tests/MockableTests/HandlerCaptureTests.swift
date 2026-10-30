import Testing

import Mockable

// A plain mock owns its handlers like any other stored property, so they are
// ordinary closures: a test can install one that captures and mutates local state,
// with no `@Sendable` annotation and no `nonisolated(unsafe)` workaround. These
// tests would not compile if the handlers were `@Sendable`.

@Mockable
protocol EventRecorder {
    func record(_ event: String)
    func flush() async throws -> Int
    var pending: Int { get async }
    subscript(index: Int) -> String { get set }
}

@Suite("Handler Capture Integration Tests")
struct HandlerCaptureTests {
    @Test("A synchronous handler mutates captured local state")
    func synchronousHandler() {
        let mock = EventRecorderMock()
        var events: [String] = []
        mock.recordHandler = { events.append($0) }

        mock.record("launch")
        mock.record("tap")

        #expect(events == ["launch", "tap"])
    }

    @Test("An async handler mutates captured local state")
    func asyncHandler() async throws {
        let mock = EventRecorderMock()
        var flushCount = 0
        mock.flushHandler = {
            flushCount += 1
            return flushCount
        }

        #expect(try await mock.flush() == 1)
        #expect(try await mock.flush() == 2)
        #expect(flushCount == 2)
    }

    @Test("An effectful property handler reads captured local state")
    func effectfulPropertyHandler() async {
        let mock = EventRecorderMock()
        var pending = 3
        mock.pendingHandler = { pending }

        pending = 5

        #expect(await mock.pending == 5)
    }

    @Test("Subscript handlers mutate captured local state")
    func subscriptHandlers() {
        let mock = EventRecorderMock()
        var storage = ["a", "b"]
        mock.subscriptIntHandler = { storage[$0] }
        mock.subscriptIntSetHandler = { storage[$0] = $1 }

        mock[1] = "c"

        #expect(mock[1] == "c")
        #expect(storage == ["a", "c"])
    }
}
