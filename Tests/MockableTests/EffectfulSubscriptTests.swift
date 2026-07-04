import Foundation
import Testing

@testable import Mockable

@Suite("Effectful Subscript Mock Tests")
struct EffectfulSubscriptTests {
    @Test("get async throws subscript returns the handler value")
    func asyncThrowsSubscriptReturnsHandlerValue() async throws {
        let mock = AsyncThrowingStoreMock()
        mock.subscriptStringHandler = { key in key.count }

        let value = try await mock["swift"]

        #expect(value == 5)
        #expect(mock.subscriptStringCallCount == 1)
        #expect(mock.subscriptStringCallArgs == ["swift"])
    }

    @Test("get async throws subscript propagates the handler error")
    func asyncThrowsSubscriptPropagatesError() async {
        let mock = AsyncThrowingStoreMock()
        mock.subscriptStringHandler = { _ in throw TestError.somethingWentWrong }

        await #expect(throws: TestError.somethingWentWrong) {
            try await mock["swift"]
        }
        #expect(mock.subscriptStringCallCount == 1)
    }

    @Test("optional get async subscript returns nil when the handler is unset")
    func optionalAsyncSubscriptDefaultsToNil() async {
        let mock = OptionalAsyncStoreMock()

        let value = await mock["missing"]

        #expect(value == nil)
        #expect(mock.subscriptStringCallCount == 1)
    }

    @Test("Sendable mock stores the effectful subscript handler behind the lock")
    func sendableEffectfulSubscript() async throws {
        let mock = SendableAsyncThrowingStoreMock()
        mock.subscriptStringHandler = { key in key.count }

        let value = try await mock["lock"]

        #expect(value == 4)
        #expect(mock.subscriptStringCallCount == 1)
    }

    @Test("resetMock clears the effectful subscript state")
    func resetMockClearsState() async throws {
        let mock = AsyncThrowingStoreMock()
        mock.subscriptStringHandler = { _ in 1 }
        _ = try await mock["a"]

        mock.resetMock()

        #expect(mock.subscriptStringCallCount == 0)
        #expect(mock.subscriptStringHandler == nil)
    }
}
