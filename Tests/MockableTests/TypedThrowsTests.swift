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

    @Test("typed throws subscript returns the handler value")
    func typedThrowsSubscriptReturnsHandlerValue() throws {
        let mock = TypedThrowingCatalogMock()
        mock.subscriptIntHandler = { id in "item-\(id)" }

        let value = try mock[4]

        #expect(value == "item-4")
        #expect(mock.subscriptIntCallCount == 1)
        #expect(mock.subscriptIntCallArgs == [4])
    }

    @Test("typed throws subscript re-throws the typed error")
    func typedThrowsSubscriptReThrowsTypedError() {
        let mock = TypedThrowingCatalogMock()
        mock.subscriptIntHandler = { _ in throw TypedThrowsError(code: 5) }

        #expect(throws: TypedThrowsError(code: 5)) {
            try mock[1]
        }
    }

    @Test("typed throws init requirement records the call")
    func typedThrowsInitializerRecordsCall() throws {
        let mock = try TypedThrowingRepositoryMock(id: "repo")

        #expect(mock.initCallCount == 1)
        #expect(mock.initCallArgs == ["repo"])
    }

    @Test("typed throws method writes inout arguments back")
    func typedThrowsInoutParameterWritesBack() throws {
        let mock = TypedThrowingParserMock()
        mock.parseHandler = { @Sendable buffer in
            (returnValue: String(decoding: buffer, as: UTF8.self), inoutArgs: [])
        }

        var buffer: [UInt8] = Array("hello".utf8)
        let value = try mock.parse(&buffer)

        #expect(value == "hello")
        #expect(buffer == [])
        #expect(mock.parseCallCount == 1)
        #expect(mock.parseCallArgs == [Array("hello".utf8)])
    }

    @Test("typed throws method with an inout parameter re-throws the typed error")
    func typedThrowsInoutParameterReThrowsTypedError() {
        let mock = TypedThrowingParserMock()
        mock.parseHandler = { _ in throw TypedThrowsError(code: 8) }

        var buffer: [UInt8] = []
        #expect(throws: TypedThrowsError(code: 8)) {
            try mock.parse(&buffer)
        }
    }

    @Test("throws(Never) method is called without try")
    func neverThrowsMethodReturnsHandlerValue() {
        let mock = NeverThrowingLoaderMock()
        mock.loadHandler = { id in "item-\(id)" }

        let value = mock.load(id: 7)

        #expect(value == "item-7")
        #expect(mock.loadCallCount == 1)
        #expect(mock.loadCallArgs == [7])
    }

    @Test("throws(Never) property is read without try")
    func neverThrowsPropertyReturnsHandlerValue() {
        let mock = NeverThrowingConfigProviderMock()
        mock.settingHandler = { 99 }

        #expect(mock.setting == 99)
        #expect(mock.settingCallCount == 1)
    }

    @Test("Sendable throws(Never) method is called without try")
    func sendableNeverThrowsMethodReturnsHandlerValue() {
        let mock = SendableNeverThrowingStoreMock()
        mock.valueHandler = { 5 }

        #expect(mock.value() == 5)
        #expect(mock.valueCallCount == 1)
    }

    @Test("throws(any Error) method returns the handler value")
    func anyErrorThrowsMethodReturnsHandlerValue() throws {
        let mock = AnyErrorThrowingLoaderMock()
        mock.loadHandler = { id in "item-\(id)" }

        let value = try mock.load(id: 3)

        #expect(value == "item-3")
        #expect(mock.loadCallCount == 1)
        #expect(mock.loadCallArgs == [3])
    }

    @Test("throws(any Error) method re-throws the handler error unchanged")
    func anyErrorThrowsMethodReThrowsHandlerError() {
        let mock = AnyErrorThrowingLoaderMock()
        mock.loadHandler = { _ in throw TypedThrowsError(code: 11) }

        #expect(throws: TypedThrowsError(code: 11)) {
            try mock.load(id: 1)
        }
    }
}
#endif
