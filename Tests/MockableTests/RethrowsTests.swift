import Foundation
import Testing

@testable import Mockable

@Suite("Rethrows Mock Tests")
struct RethrowsTests {
    @Test("rethrows mock forwards the closure to the handler and counts the call")
    func rethrowsForwardsClosureToHandler() {
        let mock = RethrowingRunnerMock()
        nonisolated(unsafe) var handlerRan = false
        mock.runHandler = { body in
            handlerRan = true
            try? body()
        }

        mock.run { }

        #expect(handlerRan)
        #expect(mock.runCallCount == 1)
    }

    @Test("rethrows mock with a return value returns the handler result")
    func rethrowsWithReturnValueReturnsHandlerResult() {
        let mock = RethrowingRunnerMock()
        mock.transformHandler = { body in
            (try? body(21)) ?? 0
        }

        let result = mock.transform { $0 * 2 }

        #expect(result == 42)
        #expect(mock.transformCallCount == 1)
    }

    @Test("Sendable rethrows mock forwards the closure to the handler")
    func sendableRethrowsForwardsClosure() {
        let mock = SendableRethrowingRunnerMock()
        nonisolated(unsafe) var handlerRan = false
        mock.runHandler = { body in
            handlerRan = true
            try? body()
        }

        mock.run { }

        #expect(handlerRan)
        #expect(mock.runCallCount == 1)
    }

    @Test("resetMock clears rethrows tracking state")
    func resetMockClearsState() {
        let mock = RethrowingRunnerMock()
        mock.runHandler = { _ in }
        mock.run { }

        mock.resetMock()

        #expect(mock.runCallCount == 0)
        #expect(mock.runHandler == nil)
    }
}
