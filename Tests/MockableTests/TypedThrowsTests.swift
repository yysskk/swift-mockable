#if compiler(>=6.0)
import Foundation
import Testing

@testable import Mockable

@Suite("Typed Throws Mock Tests")
struct TypedThrowsTests {
    @Test("typed throws method returns the handler value")
    func typedThrowsMethodReturnsHandlerValue() throws {
        let mock = TypedThrowingLoaderMock()
        mock.loadHandler = { id in "item-\(id)" }

        let value = try mock.load(id: 7)

        #expect(value == "item-7")
        #expect(mock.loadCallCount == 1)
        #expect(mock.loadCallArgs == [7])
    }

    @Test("typed throws method re-throws the typed error")
    func typedThrowsMethodReThrowsTypedError() {
        let mock = TypedThrowingLoaderMock()
        mock.loadHandler = { _ in throw TypedThrowsError(code: 42) }

        #expect(throws: TypedThrowsError(code: 42)) {
            try mock.load(id: 1)
        }
    }

    @Test("typed throws property returns the handler value")
    func typedThrowsPropertyReturnsHandlerValue() throws {
        let mock = TypedThrowingConfigProviderMock()
        mock.settingHandler = { 99 }

        let value = try mock.setting

        #expect(value == 99)
        #expect(mock.settingCallCount == 1)
    }

    @Test("typed throws property re-throws the typed error")
    func typedThrowsPropertyReThrowsTypedError() {
        let mock = TypedThrowingConfigProviderMock()
        mock.settingHandler = { throw TypedThrowsError(code: 7) }

        #expect(throws: TypedThrowsError(code: 7)) {
            try mock.setting
        }
    }

    @Test("Sendable typed throws method re-throws the typed error")
    func sendableTypedThrowsMethod() {
        let mock = SendableTypedThrowingStoreMock()
        mock.valueHandler = { throw TypedThrowsError(code: 3) }

        #expect(throws: TypedThrowsError(code: 3)) {
            try mock.value()
        }
        #expect(mock.valueCallCount == 1)
    }

    @Test("child mock of a typed-throws parent has no availability restriction")
    func typedThrowsInheritance() throws {
        let mock = TypedThrowingChildMock()
        mock.baseHandler = { 5 }
        mock.childHandler = { "child" }

        #expect(try mock.base() == 5)
        #expect(mock.child() == "child")
    }

    @Test("generic typed throws method re-throws the generic error")
    func genericTypedThrowsMethod() {
        let mock = GenericTypedThrowingRunnerMock()
        mock.runHandler = { body in try body() }

        #expect(throws: TypedThrowsError(code: 9)) {
            try mock.run { throw TypedThrowsError(code: 9) }
        }
        #expect(mock.runCallCount == 1)
    }

    @Test("concrete typed-throws closure parameter is forwarded to an untyped handler")
    func concreteTypedThrowsClosureParameter() {
        let mock = ConcreteTypedThrowingClosureServiceMock()
        nonisolated(unsafe) var handlerRan = false
        mock.performHandler = { body in
            handlerRan = true
            try? body()
        }

        mock.perform { }

        #expect(handlerRan)
        #expect(mock.performCallCount == 1)
    }
}
#endif
