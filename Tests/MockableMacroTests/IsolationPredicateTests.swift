import SwiftSyntax
import Testing

@testable import MockableMacros

@Suite("Isolation Predicate Tests")
struct IsolationPredicateTests {
    private func decl(_ source: String) -> DeclSyntax {
        "\(raw: source)"
    }

    @Test(
        "A requirement leaves the mock's isolation when nonisolated or taking an isolated parameter",
        arguments: [
            ("nonisolated func track()", true),
            ("nonisolated var id: String { get }", true),
            ("nonisolated subscript(key: String) -> Int { get }", true),
            ("func run(on actor: isolated any Actor) async", true),
            ("func run(_ value: Int, on actor: isolated some Actor)", true),
            ("init(on actor: isolated any Actor)", true),
            ("subscript(on actor: isolated any Actor) -> Int { get }", true),
            ("func load()", false),
            ("func send(_ value: sending Int)", false),
            ("var title: String { get }", false),
            ("init(name: String)", false),
            ("associatedtype Item", false),
        ]
    )
    func leavesMockIsolation(source: String, expected: Bool) {
        #expect(Requirement(decl(source)).leavesMockIsolation == expected)
    }
}
