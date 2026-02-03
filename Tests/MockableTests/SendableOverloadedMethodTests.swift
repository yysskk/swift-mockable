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
