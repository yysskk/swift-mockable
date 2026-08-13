import Testing

import Mockable

@Mockable
protocol DiscardableResultService {
    @discardableResult
    func run() -> Int
}

@Suite("Witness Attribute Integration Tests")
struct WitnessAttributeTests {
    @Test("A @discardableResult requirement's result can be discarded on the mock")
    func discardableResult() {
        let mock = DiscardableResultServiceMock()
        mock.runHandler = { 1 }

        // Without the attribute on the witness this line warns about an unused result.
        mock.run()

        #expect(mock.runCallCount == 1)
    }
}
