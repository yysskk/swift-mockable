import Foundation
import Testing

import Mockable

// MARK: - Sendable Overloaded Method Tests

@Suite("Sendable Overloaded Method Tests")
struct SendableOverloadedMethodTests {
    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
    @Test("Overloaded methods have separate call counts")
    func overloadedMethodsSeparateCallCounts() async {
        let mock = OverloadedUserDefaultsMock()

        mock.setBoolStringHandler = { @Sendable _ in }
        mock.setIntStringHandler = { @Sendable _ in }
        mock.setStringStringHandler = { @Sendable _ in }

        await mock.set(true, forKey: "boolKey")
        await mock.set(42, forKey: "intKey")
        await mock.set(100, forKey: "intKey2")
        await mock.set("hello", forKey: "stringKey")

        #expect(mock.setBoolStringCallCount == 1)
        #expect(mock.setIntStringCallCount == 2)
        #expect(mock.setStringStringCallCount == 1)
    }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
    @Test("Overloaded methods have separate call args")
    func overloadedMethodsSeparateCallArgs() async {
        let mock = OverloadedUserDefaultsMock()

        mock.setBoolStringHandler = { @Sendable _ in }
        mock.setIntStringHandler = { @Sendable _ in }
        mock.setStringStringHandler = { @Sendable _ in }

        await mock.set(true, forKey: "enabled")
        await mock.set(42, forKey: "count")
        await mock.set("value", forKey: "name")

        #expect(mock.setBoolStringCallArgs.count == 1)
        #expect(mock.setBoolStringCallArgs[0].0 == true)
        #expect(mock.setBoolStringCallArgs[0].forKey == "enabled")

        #expect(mock.setIntStringCallArgs.count == 1)
        #expect(mock.setIntStringCallArgs[0].0 == 42)
        #expect(mock.setIntStringCallArgs[0].forKey == "count")

        #expect(mock.setStringStringCallArgs.count == 1)
        #expect(mock.setStringStringCallArgs[0].0 == "value")
        #expect(mock.setStringStringCallArgs[0].forKey == "name")
    }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
    @Test("Overloaded methods have separate handlers")
    func overloadedMethodsSeparateHandlers() async {
        let mock = OverloadedUserDefaultsMock()
        nonisolated(unsafe) var boolHandlerCalled = false
        nonisolated(unsafe) var intHandlerCalled = false
        nonisolated(unsafe) var stringHandlerCalled = false

        mock.setBoolStringHandler = { @Sendable _ in
            boolHandlerCalled = true
        }
        mock.setIntStringHandler = { @Sendable _ in
            intHandlerCalled = true
        }
        mock.setStringStringHandler = { @Sendable _ in
            stringHandlerCalled = true
        }

        await mock.set(true, forKey: "key")
        #expect(boolHandlerCalled)
        #expect(!intHandlerCalled)
        #expect(!stringHandlerCalled)

        await mock.set(42, forKey: "key")
        #expect(intHandlerCalled)
        #expect(!stringHandlerCalled)

        await mock.set("value", forKey: "key")
        #expect(stringHandlerCalled)
    }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
    @Test("Non-overloaded method retains simple naming")
    func nonOverloadedMethodSimpleNaming() async {
        let mock = OverloadedUserDefaultsMock()

        mock.getValueHandler = { @Sendable in "result" }

        let result = await mock.getValue()

        #expect(result == "result")
        #expect(mock.getValueCallCount == 1)
    }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
    @Test("Reset clears all overloaded method states")
    func resetClearsOverloadedMethodStates() async {
        let mock = OverloadedUserDefaultsMock()

        mock.setBoolStringHandler = { @Sendable _ in }
        mock.setIntStringHandler = { @Sendable _ in }
        mock.setStringStringHandler = { @Sendable _ in }
        mock.getValueHandler = { @Sendable in "result" }

        await mock.set(true, forKey: "key")
        await mock.set(42, forKey: "key")
        await mock.set("value", forKey: "key")
        _ = await mock.getValue()

        #expect(mock.setBoolStringCallCount == 1)
        #expect(mock.setIntStringCallCount == 1)
        #expect(mock.setStringStringCallCount == 1)
        #expect(mock.getValueCallCount == 1)

        mock.resetMock()

        #expect(mock.setBoolStringCallCount == 0)
        #expect(mock.setIntStringCallCount == 0)
        #expect(mock.setStringStringCallCount == 0)
        #expect(mock.getValueCallCount == 0)
        #expect(mock.setBoolStringCallArgs.isEmpty)
        #expect(mock.setIntStringCallArgs.isEmpty)
        #expect(mock.setStringStringCallArgs.isEmpty)
    }
}

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
