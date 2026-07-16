import Foundation
import Testing

import Mockable

// The default (.debug) and the explicit .debug spelling both compile here because
// tests build in the debug configuration.
@Mockable(condition: .debug)
protocol ExplicitDebugConditionService {
    func value() -> Int
}

@Mockable(condition: .always)
protocol AlwaysCompiledService {
    func greet(name: String) -> String
}

// Pins the public type name: the qualified spelling must resolve against the
// `Mockable` module's declaration.
@Mockable(condition: MockCompilationCondition.always)
protocol QualifiedAlwaysService {
    func run()
}

// MOCKABLE_RUNTIME_TEST_CONDITION is defined for this test target in every
// package manifest. If the flag stopped being applied, this file would fail to
// compile because the mock would not exist.
@Mockable(condition: .custom("MOCKABLE_RUNTIME_TEST_CONDITION"))
protocol CustomConditionService {
    func isEnabled() -> Bool
    var identifier: String { get }
}

@Suite("Compilation Condition Argument Tests")
struct CompilationConditionArgumentTests {
    @Test("Explicit .debug mock behaves like a default mock")
    func explicitDebugMock() {
        let mock = ExplicitDebugConditionServiceMock()

        mock.valueHandler = { 42 }

        #expect(mock.value() == 42)
        #expect(mock.valueCallCount == 1)

        mock.resetMock()
        #expect(mock.valueCallCount == 0)
    }

    @Test(".always mock records calls and resets")
    func alwaysMock() {
        let mock = AlwaysCompiledServiceMock()

        mock.greetHandler = { name in "Hello, \(name)!" }

        #expect(mock.greet(name: "World") == "Hello, World!")
        #expect(mock.greetCallCount == 1)
        #expect(mock.greetCallArgs == ["World"])

        mock.resetMock()
        #expect(mock.greetCallCount == 0)
        #expect(mock.greetCallArgs.isEmpty)
    }

    @Test("Type-qualified .always mock works")
    func qualifiedAlwaysMock() {
        let mock = QualifiedAlwaysServiceMock()

        mock.runHandler = { }
        mock.run()

        #expect(mock.runCallCount == 1)
    }

    @Test(".custom mock exists when its flag is defined")
    func customConditionMock() {
        let mock = CustomConditionServiceMock()

        mock.isEnabledHandler = { true }
        mock._identifier = "custom"

        #expect(mock.isEnabled())
        #expect(mock.isEnabledCallCount == 1)
        #expect(mock.identifier == "custom")

        mock.resetMock()
        #expect(mock.isEnabledCallCount == 0)
        #expect(mock._identifier == nil)
    }

    @Test(".always mock conforms to the protocol")
    func alwaysMockConformsToProtocol() {
        func useService(_ service: AlwaysCompiledService) -> String {
            service.greet(name: "swift")
        }

        let mock = AlwaysCompiledServiceMock()
        mock.greetHandler = { name in "Hi, \(name)" }

        #expect(useService(mock) == "Hi, swift")
    }
}
