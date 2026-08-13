import Testing

import Mockable

// Inheritance clauses naming something other than a `@Mockable` parent protocol.
// Compiling these mocks is most of the test: each conformance was previously taken
// for a parent protocol, so the mock inherited from a type that does not exist.

@Mockable
protocol QualifiedSendableService: Swift.Sendable {
    func run() -> Int
}

@Mockable
protocol ClassBoundService: AnyObject {
    func run() -> Int
}

@Mockable
protocol FailureReason: Error {
    var code: Int { get }
}

/// A protocol whose name has to be escaped. The mock's name is a plain identifier.
@Mockable
protocol `Type` {
    func run() -> Int
}

@Suite("Inherited Type Integration Tests")
struct InheritedTypeTests {
    @Test("A module-qualified Sendable conformance produces a Sendable mock")
    func qualifiedSendableConformance() {
        let mock = QualifiedSendableServiceMock()
        mock.runHandler = { 1 }

        #expect(mock.run() == 1)
        #expect(mock.runCallCount == 1)

        // The mock is Sendable, so it can cross an isolation boundary.
        let sendable: any Sendable = mock
        #expect(sendable is QualifiedSendableServiceMock)
    }

    @Test("A class-bound protocol produces an ordinary mock")
    func classBoundConformance() {
        let mock = ClassBoundServiceMock()
        mock.runHandler = { 2 }

        #expect(mock.run() == 2)
        #expect(mock.runCallCount == 1)
    }

    @Test("An Error conformance produces a mock usable as an error")
    func errorConformance() {
        let mock = FailureReasonMock()
        mock._code = 42

        #expect(mock.code == 42)

        let error: any Error = mock
        #expect((error as? FailureReasonMock)?.code == 42)
    }

    @Test("An escaped protocol name produces a plain mock type name")
    func escapedProtocolName() {
        let mock = TypeMock()
        mock.runHandler = { 3 }

        #expect(mock.run() == 3)
    }
}
