import Foundation
import Testing

import Mockable

@Mockable
protocol SeparateParamsService {
    func add(a: Int, b: Int) -> Int
}

@Mockable
protocol SeparateParamsSendableService: Sendable {
    func combine(x: Int, y: Int) -> String
}

@Mockable
protocol SeparateParamsGrid {
    subscript(row: Int, col: Int) -> Int { get set }
}

@Suite("Multi-Parameter Handler Runtime Tests")
struct MultiParameterHandlerRuntimeTests {
    @Test("Handler takes individual parameters, not a tuple")
    func individualParameterHandler() {
        let mock = SeparateParamsServiceMock()

        // The closure takes `a, b` directly rather than `$0.a + $0.b`.
        mock.addHandler = { a, b in a + b }

        #expect(mock.add(a: 2, b: 3) == 5)
        #expect(mock.addCallCount == 1)
        // CallArgs remains a labeled tuple regardless of handler style.
        #expect(mock.addCallArgs.count == 1)
        #expect(mock.addCallArgs[0].a == 2)
        #expect(mock.addCallArgs[0].b == 3)
    }

    @Test("Sendable mock (lock-based) uses individual-parameter handler")
    func sendableIndividualParameterHandler() {
        let mock = SeparateParamsSendableServiceMock()

        mock.combineHandler = { x, y in "\(x)-\(y)" }

        #expect(mock.combine(x: 1, y: 2) == "1-2")
        #expect(mock.combineCallCount == 1)
        #expect(mock.combineCallArgs[0].x == 1)
        #expect(mock.combineCallArgs[0].y == 2)
    }

    @Test("Subscript getter and setter handlers take individual parameters")
    func subscriptIndividualParameterHandlers() {
        let mock = SeparateParamsGridMock()

        mock.subscriptIntIntHandler = { row, col in row * 10 + col }
        #expect(mock[1, 2] == 12)
        #expect(mock.subscriptIntIntCallCount == 1)
        #expect(mock.subscriptIntIntCallArgs[0].row == 1)
        #expect(mock.subscriptIntIntCallArgs[0].col == 2)

        nonisolated(unsafe) var captured: (Int, Int, Int)?
        mock.subscriptIntIntSetHandler = { row, col, value in
            captured = (row, col, value)
        }
        mock[3, 4] = 99
        #expect(captured?.0 == 3)
        #expect(captured?.1 == 4)
        #expect(captured?.2 == 99)
    }
}
