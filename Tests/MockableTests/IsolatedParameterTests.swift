import Testing

import Mockable

// A requirement with an `isolated` parameter on a `@MainActor` protocol. Its witness is
// isolated to the argument rather than to the mock, so it cannot record into isolated
// tracking state — compiling this mock is most of the test.

@MainActor
@Mockable
protocol IsolatedRunner {
    func run(on actor: isolated any Actor) async -> Int
    subscript(on actor: isolated any Actor) -> Int { get }
    func load()
}

private actor Worker {}

@Suite("Isolated Parameter Tests")
struct IsolatedParameterTests {
    @Test("A requirement with an isolated parameter is tracked without hopping to the main actor")
    func isolatedParameterRequirement() async {
        let mock = IsolatedRunnerMock()
        mock.runHandler = { _ in 7 }
        mock.subscriptIsolatedanyActorHandler = { _ in 3 }
        let worker = Worker()

        #expect(await mock.run(on: worker) == 7)
        #expect(await mock[on: worker] == 3)

        #expect(mock.runCallCount == 1)
        #expect(mock.runCallArguments.count == 1)
        #expect(mock.subscriptIsolatedanyActorCallCount == 1)

        mock.resetMock()

        #expect(mock.runCallCount == 0)
        #expect(mock.runHandler == nil)
        #expect(mock.subscriptIsolatedanyActorCallCount == 0)
    }

    @Test("An isolated requirement of the same protocol still works")
    @MainActor
    func isolatedMembersStillWork() {
        let mock = IsolatedRunnerMock()
        mock.loadHandler = { }

        mock.load()

        #expect(mock.loadCallCount == 1)
        mock.resetMock()
        #expect(mock.loadCallCount == 0)
    }
}
