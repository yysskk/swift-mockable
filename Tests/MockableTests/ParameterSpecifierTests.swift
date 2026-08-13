import Testing

import Mockable

// Parameters carrying a specifier. A specifier is only valid in parameter position, so
// the mock's stored properties and handler types have to drop it, and an ownership
// specifier also limits how often the witness may use the argument.

struct SpecifiedPayload: Sendable, Equatable {
    let id: Int
}

@Mockable
protocol ParameterSpecifierService {
    func consume(_ item: consuming SpecifiedPayload)
    func inspect(_ item: borrowing SpecifiedPayload)
    func send(_ item: sending SpecifiedPayload)
}

@Mockable
protocol ParameterSpecifierSendableService: Sendable {
    func consume(_ item: consuming SpecifiedPayload)
}

@Mockable
protocol InOutSpecifierService {
    func fill(_ value: inout Int!)
    func replace<T>(_ values: inout [T])
}

@Suite("Parameter Specifier Integration Tests")
struct ParameterSpecifierTests {
    @Test("A consuming parameter is recorded and forwarded")
    func consumingParameter() {
        let mock = ParameterSpecifierServiceMock()
        nonisolated(unsafe) var received: SpecifiedPayload?
        mock.consumeHandler = { received = $0 }

        mock.consume(SpecifiedPayload(id: 1))

        #expect(mock.consumeCallCount == 1)
        #expect(mock.consumeCallArgs == [SpecifiedPayload(id: 1)])
        #expect(received == SpecifiedPayload(id: 1))
    }

    @Test("A borrowing parameter is recorded and forwarded")
    func borrowingParameter() {
        let mock = ParameterSpecifierServiceMock()
        nonisolated(unsafe) var received: SpecifiedPayload?
        mock.inspectHandler = { received = $0 }

        mock.inspect(SpecifiedPayload(id: 2))

        #expect(mock.inspectCallArgs == [SpecifiedPayload(id: 2)])
        #expect(received == SpecifiedPayload(id: 2))
    }

    @Test("A sending parameter is recorded and forwarded")
    func sendingParameter() {
        let mock = ParameterSpecifierServiceMock()
        mock.sendHandler = { _ in }

        mock.send(SpecifiedPayload(id: 3))

        #expect(mock.sendCallArgs == [SpecifiedPayload(id: 3)])
    }

    @Test("A consuming parameter of a Sendable mock is recorded behind the lock")
    func consumingParameterOnSendableMock() {
        let mock = ParameterSpecifierSendableServiceMock()
        mock.consumeHandler = { _ in }

        mock.consume(SpecifiedPayload(id: 4))

        #expect(mock.consumeCallCount == 1)
        #expect(mock.consumeCallArgs == [SpecifiedPayload(id: 4)])
    }

    @Test("An implicitly unwrapped optional inout argument is written back")
    func implicitlyUnwrappedOptionalInOut() {
        let mock = InOutSpecifierServiceMock()
        mock.fillHandler = { _ in 42 }

        var value: Int! = nil
        mock.fill(&value)

        #expect(value == 42)
        #expect(mock.fillCallCount == 1)
    }

    @Test("A generic inout argument is cast back to its own type")
    func genericInOut() {
        let mock = InOutSpecifierServiceMock()
        mock.replaceHandler = { _ in [7, 8] }

        var values = [1, 2, 3]
        mock.replace(&values)

        #expect(values == [7, 8])
    }
}
