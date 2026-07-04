import Foundation
import Testing

@testable import Mockable

@Suite("Non-Escaping Closure Mock Tests")
struct NonEscapingClosureTests {
    @Test("Non-escaping closure is forwarded to the handler and the call is counted")
    func nonEscapingClosureForwardedToHandler() {
        let mock = NonEscapingClosureServiceMock()
        nonisolated(unsafe) var handlerRan = false
        mock.runHandler = { body in
            body()
        }

        mock.run { handlerRan = true }

        #expect(handlerRan)
        #expect(mock.runCallCount == 1)
        // CallArgs excludes the non-escaping closure, so it records the empty tuple.
        #expect(mock.runCallArgs.count == 1)
    }

    @Test("Storable parameters are recorded while the non-escaping closure is forwarded")
    func storableParametersRecorded() {
        let mock = NonEscapingClosureServiceMock()
        mock.computeHandler = { _, body in
            body() * 2
        }

        let result = mock.compute(label: "double") { 21 }

        #expect(result == 42)
        #expect(mock.computeCallCount == 1)
        #expect(mock.computeCallArgs == ["double"])
    }

    @Test("Sendable mock forwards a non-escaping @Sendable closure to the handler")
    func sendableMockForwardsNonEscapingClosure() {
        let mock = SendableNonEscapingClosureServiceMock()
        nonisolated(unsafe) var handlerRan = false
        mock.performHandler = { body in
            body()
        }

        mock.perform { handlerRan = true }

        #expect(handlerRan)
        #expect(mock.performCallCount == 1)
    }

    @Test("resetMock clears non-escaping closure tracking state")
    func resetMockClearsState() {
        let mock = NonEscapingClosureServiceMock()
        mock.runHandler = { $0() }
        mock.run {}

        mock.resetMock()

        #expect(mock.runCallCount == 0)
        #expect(mock.runCallArgs.isEmpty)
        #expect(mock.runHandler == nil)
    }
}
