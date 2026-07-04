import Foundation
import Testing

@testable import Mockable

@Suite("Autoclosure Mock Tests")
struct AutoclosureTests {
    @Test("@autoclosure argument is recorded by value")
    func autoclosureArgumentIsRecordedByValue() {
        let mock = AutoclosureLoggingServiceMock()

        mock.log("hello")
        mock.log("world")

        #expect(mock.logCallCount == 2)
        #expect(mock.logCallArgs == ["hello", "world"])
    }

    @Test("handler receives the evaluated value")
    func handlerReceivesEvaluatedValue() {
        let mock = AutoclosureLoggingServiceMock()
        nonisolated(unsafe) var received: [String] = []
        mock.logHandler = { message in
            received.append(message)
        }

        mock.log("evaluated")

        #expect(received == ["evaluated"])
    }

    @Test("@autoclosure argument is evaluated exactly once per call")
    func autoclosureArgumentIsEvaluatedExactlyOncePerCall() {
        let mock = AutoclosureLoggingServiceMock()
        var evaluationCount = 0
        func nextMessage() -> String {
            evaluationCount += 1
            return "message-\(evaluationCount)"
        }
        mock.logHandler = { _ in }

        mock.log(nextMessage())

        #expect(evaluationCount == 1)
        #expect(mock.logCallArgs == ["message-1"])
    }

    @Test("@autoclosure argument is evaluated even when no handler is set")
    func autoclosureArgumentIsEvaluatedWithoutHandler() {
        let mock = AutoclosureLoggingServiceMock()
        var evaluationCount = 0
        func nextValue() -> String {
            evaluationCount += 1
            return "value"
        }

        mock.log(nextValue())

        #expect(evaluationCount == 1)
        #expect(mock.logCallCount == 1)
    }

    @Test("mixed parameters record a labeled tuple with the evaluated value")
    func mixedParametersRecordLabeledTuple() {
        let mock = AutoclosureLoggingServiceMock()
        mock.combineHandler = { prefix, message in
            "\(prefix): \(message)"
        }

        let result = mock.combine(prefix: "INFO", message: "ready")

        #expect(result == "INFO: ready")
        #expect(mock.combineCallArgs.count == 1)
        #expect(mock.combineCallArgs[0].prefix == "INFO")
        #expect(mock.combineCallArgs[0].message == "ready")
    }

    @Test("@autoclosure @escaping argument is evaluated the same way")
    func escapingAutoclosureArgumentIsEvaluated() {
        let mock = AutoclosureLoggingServiceMock()
        nonisolated(unsafe) var received: [Int] = []
        mock.scheduleHandler = { value in
            received.append(value)
        }

        mock.schedule(21 + 21)

        #expect(received == [42])
        #expect(mock.scheduleCallArgs == [42])
    }

    @Test("throwing autoclosure propagates its error before recording the call")
    func throwingAutoclosurePropagatesErrorBeforeRecording() {
        let mock = AutoclosureThrowingServiceMock()
        mock.computeHandler = { value in
            value * 2
        }
        func failingValue() throws -> Int {
            throw TestError.somethingWentWrong
        }

        #expect(throws: TestError.somethingWentWrong) {
            try mock.compute(try failingValue())
        }
        #expect(mock.computeCallCount == 0)
        #expect(mock.computeCallArgs.isEmpty)
    }

    @Test("throwing autoclosure evaluates successfully and forwards to the handler")
    func throwingAutoclosureEvaluatesAndForwards() throws {
        let mock = AutoclosureThrowingServiceMock()
        mock.computeHandler = { value in
            value * 2
        }

        let result = try mock.compute(21)

        #expect(result == 42)
        #expect(mock.computeCallArgs == [21])
    }

    @Test("Sendable mock evaluates and records autoclosure arguments")
    func sendableMockRecordsAutoclosureArguments() {
        let mock = AutoclosureSendableServiceMock()

        mock.record(40 + 2)

        #expect(mock.recordCallCount == 1)
        #expect(mock.recordCallArgs == [42])
    }

    @Test("subscript with autoclosure key records the evaluated key")
    func subscriptWithAutoclosureKeyRecordsEvaluatedKey() {
        let mock = AutoclosureSubscriptServiceMock()
        mock.subscriptAutoclosureStringHandler = { key in
            key.count
        }

        let value = mock["swift"]

        #expect(value == 5)
        #expect(mock.subscriptAutoclosureStringCallCount == 1)
        #expect(mock.subscriptAutoclosureStringCallArgs == ["swift"])
    }

    @Test("resetMock clears autoclosure tracking state")
    func resetMockClearsTrackingState() {
        let mock = AutoclosureLoggingServiceMock()
        mock.logHandler = { _ in }
        mock.log("hello")

        mock.resetMock()

        #expect(mock.logCallCount == 0)
        #expect(mock.logCallArgs.isEmpty)
        #expect(mock.logHandler == nil)
    }
}
