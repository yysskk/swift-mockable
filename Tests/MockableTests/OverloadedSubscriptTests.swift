import Foundation
import Testing

import Mockable

@Mockable
protocol OverloadedSubscriptService {
    subscript(key: String) -> Int { get }
    subscript(key: String) -> Bool { get set }
}

@Mockable
protocol SendableOverloadedSubscriptService: Sendable {
    subscript(key: String) -> Int { get }
    subscript(key: String) -> Bool { get }
}

@Suite("Overloaded Subscript Mock Tests")
struct OverloadedSubscriptTests {
    @Test("Subscripts with identical parameters are tracked independently")
    func independentTracking() {
        let mock = OverloadedSubscriptServiceMock()
        mock.subscriptStringIntHandler = { key in key.count }
        mock.subscriptStringBoolHandler = { key in key.isEmpty }

        let count: Int = mock["swift"]
        let isEmpty: Bool = mock[""]

        #expect(count == 5)
        #expect(isEmpty)
        #expect(mock.subscriptStringIntCallCount == 1)
        #expect(mock.subscriptStringIntCallArgs == ["swift"])
        #expect(mock.subscriptStringBoolCallCount == 1)
        #expect(mock.subscriptStringBoolCallArgs == [""])
    }

    @Test("The overloaded get-set subscript uses its own set handler")
    func setHandlerRouting() {
        let mock = OverloadedSubscriptServiceMock()
        nonisolated(unsafe) var received: (key: String, value: Bool)?
        mock.subscriptStringBoolSetHandler = { key, value in
            received = (key, value)
        }

        mock["flag"] = true

        #expect(received?.key == "flag")
        #expect(received?.value == true)
    }

    @Test("resetMock clears both overloads")
    func resetClearsBothOverloads() {
        let mock = OverloadedSubscriptServiceMock()
        mock.subscriptStringIntHandler = { _ in 0 }
        mock.subscriptStringBoolHandler = { _ in false }
        _ = mock["a"] as Int
        _ = mock["b"] as Bool

        mock.resetMock()

        #expect(mock.subscriptStringIntCallCount == 0)
        #expect(mock.subscriptStringIntCallArgs.isEmpty)
        #expect(mock.subscriptStringIntHandler == nil)
        #expect(mock.subscriptStringBoolCallCount == 0)
        #expect(mock.subscriptStringBoolCallArgs.isEmpty)
        #expect(mock.subscriptStringBoolHandler == nil)
    }

    @Test("A Sendable mock tracks overloaded subscripts behind the lock")
    func sendableOverloadedSubscripts() {
        let mock = SendableOverloadedSubscriptServiceMock()
        mock.subscriptStringIntHandler = { key in key.count }
        mock.subscriptStringBoolHandler = { key in key.isEmpty }

        let count: Int = mock["actor"]
        let isEmpty: Bool = mock["actor"]

        #expect(count == 5)
        #expect(!isEmpty)
        #expect(mock.subscriptStringIntCallCount == 1)
        #expect(mock.subscriptStringBoolCallCount == 1)
    }
}
