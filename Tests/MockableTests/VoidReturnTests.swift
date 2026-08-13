import Testing

import Mockable

// Every spelling of a `Void` return. A requirement returning nothing is a no-op when
// its handler is unset, whichever way it is written.

@Mockable
protocol VoidReturnService {
    func plain()
    func explicit() -> Void
    func qualified() -> Swift.Void
    func parenthesized() -> (Void)
    func emptyTuple() -> ()
}

@Suite("Void Return Integration Tests")
struct VoidReturnTests {
    @Test("Every Void spelling is a no-op when its handler is unset")
    func unsetHandlerIsANoOp() {
        let mock = VoidReturnServiceMock()

        mock.plain()
        mock.explicit()
        mock.qualified()
        mock.parenthesized()
        mock.emptyTuple()

        #expect(mock.plainCallCount == 1)
        #expect(mock.explicitCallCount == 1)
        #expect(mock.qualifiedCallCount == 1)
        #expect(mock.parenthesizedCallCount == 1)
        #expect(mock.emptyTupleCallCount == 1)
    }

    @Test("Every Void spelling forwards to its handler")
    func handlerIsInvoked() {
        let mock = VoidReturnServiceMock()
        nonisolated(unsafe) var calls: [String] = []
        mock.qualifiedHandler = { calls.append("qualified") }
        mock.parenthesizedHandler = { calls.append("parenthesized") }

        mock.qualified()
        mock.parenthesized()

        #expect(calls == ["qualified", "parenthesized"])
    }
}
