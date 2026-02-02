import Foundation
import Testing

import Mockable

// MARK: - Actor Overloaded Method Tests

@Suite("Actor Overloaded Method Tests")
struct ActorOverloadedMethodTests {
    @Test("Actor overloaded methods have separate call counts")
    func actorOverloadedMethodsSeparateCallCounts() async {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = ActorOverloadedServiceMock()

        mock.processIntHandler = { @Sendable _ in }
        mock.processStringHandler = { @Sendable _ in }

        await mock.process(42)
        await mock.process("hello")
        await mock.process(100)

        #expect(mock.processIntCallCount == 2)
        #expect(mock.processStringCallCount == 1)
    }

    @Test("Actor overloaded methods have separate call args")
    func actorOverloadedMethodsSeparateCallArgs() async {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = ActorOverloadedServiceMock()

        mock.processIntHandler = { @Sendable _ in }
        mock.processStringHandler = { @Sendable _ in }

        await mock.process(42)
        await mock.process("hello")

        #expect(mock.processIntCallArgs == [42])
        #expect(mock.processStringCallArgs == ["hello"])
    }

    @Test("Actor non-overloaded method retains simple naming")
    func actorNonOverloadedMethodSimpleNaming() async {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = ActorOverloadedServiceMock()

        mock.fetchHandler = { @Sendable in "result" }

        let result = await mock.fetch()

        #expect(result == "result")
        #expect(mock.fetchCallCount == 1)
    }

    @Test("Actor overloaded methods reset correctly")
    func actorOverloadedMethodsResetCorrectly() async {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = ActorOverloadedServiceMock()

        mock.processIntHandler = { @Sendable _ in }
        mock.processStringHandler = { @Sendable _ in }
        mock.fetchHandler = { @Sendable in "result" }

        await mock.process(42)
        await mock.process("hello")
        _ = await mock.fetch()

        #expect(mock.processIntCallCount == 1)
        #expect(mock.processStringCallCount == 1)
        #expect(mock.fetchCallCount == 1)

        mock.resetMock()

        #expect(mock.processIntCallCount == 0)
        #expect(mock.processStringCallCount == 0)
        #expect(mock.fetchCallCount == 0)
        #expect(mock.processIntCallArgs.isEmpty)
        #expect(mock.processStringCallArgs.isEmpty)
    }
}
