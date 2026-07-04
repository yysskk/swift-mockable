import Foundation
import Testing

@testable import Mockable

@Suite("Effectful Accessor Mock Tests")
struct EffectfulAccessorTests {
    @Test("get async throws property returns the handler value")
    func asyncThrowsGetterReturnsHandlerValue() async throws {
        let mock = TokenProvidingMock()
        mock.tokenHandler = { "secret" }

        let token = try await mock.token

        #expect(token == "secret")
        #expect(mock.tokenCallCount == 1)
    }

    @Test("get async throws property propagates the handler error")
    func asyncThrowsGetterPropagatesError() async {
        let mock = TokenProvidingMock()
        mock.tokenHandler = { throw TestError.somethingWentWrong }

        await #expect(throws: TestError.somethingWentWrong) {
            try await mock.token
        }
        #expect(mock.tokenCallCount == 1)
    }

    @Test("get throws property returns the handler value")
    func throwingGetterReturnsHandlerValue() throws {
        let mock = ThrowingConfigProvidingMock()
        mock.maxRetryCountHandler = { 3 }

        let value = try mock.maxRetryCount

        #expect(value == 3)
        #expect(mock.maxRetryCountCallCount == 1)
    }

    @Test("get throws property propagates the handler error")
    func throwingGetterPropagatesError() {
        let mock = ThrowingConfigProvidingMock()
        mock.maxRetryCountHandler = { throw TestError.somethingWentWrong }

        #expect(throws: TestError.somethingWentWrong) {
            try mock.maxRetryCount
        }
    }

    @Test("optional get async property returns nil when the handler is unset")
    func optionalAsyncGetterDefaultsToNil() async {
        let mock = AsyncCacheProvidingMock()

        let value = await mock.cachedValue

        #expect(value == nil)
        #expect(mock.cachedValueCallCount == 1)
    }

    @Test("call count increments on every access")
    func callCountIncrementsPerAccess() async throws {
        let mock = TokenProvidingMock()
        mock.tokenHandler = { "token" }

        _ = try await mock.token
        _ = try await mock.token
        _ = try await mock.token

        #expect(mock.tokenCallCount == 3)
    }

    @Test("Sendable mock stores the effectful handler behind the lock")
    func sendableMockHandlesEffectfulProperty() async throws {
        let mock = SendableRemoteConfigMock()
        mock.flagHandler = { true }

        let flag = try await mock.flag

        #expect(flag == true)
        #expect(mock.flagCallCount == 1)
    }

    @Test("static effectful property tracks calls through static storage")
    func staticEffectfulPropertyTracksCalls() throws {
        StaticKeyProvidingMock.apiKeyHandler = { "key-123" }
        defer { StaticKeyProvidingMock().resetMock() }

        let key = try StaticKeyProvidingMock.apiKey

        #expect(key == "key-123")
        #expect(StaticKeyProvidingMock.apiKeyCallCount == 1)
    }

    @Test("actor mock exposes the effectful property through actor isolation")
    func actorMockHandlesEffectfulProperty() async throws {
        let mock = ActorTokenStoreMock()
        mock.tokenHandler = { "actor-secret" }

        let token = try await mock.token

        #expect(token == "actor-secret")
        #expect(mock.tokenCallCount == 1)
    }

    @Test("resetMock clears the effectful property state")
    func resetMockClearsEffectfulState() async throws {
        let mock = TokenProvidingMock()
        mock.tokenHandler = { "token" }
        _ = try await mock.token

        mock.resetMock()

        #expect(mock.tokenCallCount == 0)
        #expect(mock.tokenHandler == nil)
    }
}
