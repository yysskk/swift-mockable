import SwiftSyntax
import Testing

@testable import MockableMacros

@Suite("Default Return Value Tests")
struct DefaultReturnValueTests {
    private func defaultStatement(for source: String?) -> String? {
        MockGenerator.defaultReturnStatement(for: source.map { TypeSyntax(stringLiteral: $0) })
    }

    @Test("No return type has no default")
    func noReturnType() {
        #expect(defaultStatement(for: nil) == nil)
    }

    @Test(
        "Optional spellings default to nil",
        arguments: ["Int?", "Int!", "Optional<Int>", "Swift.Optional<Int>", "[Int]?", "Set<Int>?"]
    )
    func optionalDefaults(source: String) {
        #expect(defaultStatement(for: source) == "return nil")
    }

    @Test(
        "Array and set spellings default to an empty collection",
        arguments: ["[Int]", "Array<Int>", "Swift.Array<Int>", "Set<Int>", "Swift.Set<Int>"]
    )
    func arrayAndSetDefaults(source: String) {
        #expect(defaultStatement(for: source) == "return []")
    }

    @Test(
        "Dictionary spellings default to an empty dictionary",
        arguments: ["[String: Int]", "Dictionary<String, Int>", "Swift.Dictionary<String, Int>"]
    )
    func dictionaryDefaults(source: String) {
        #expect(defaultStatement(for: source) == "return [:]")
    }

    @Test(
        "Types without a natural empty value have no default",
        arguments: ["Int", "String", "User", "() -> Void", "MySet<Int>", "Set"]
    )
    func typesWithoutDefaults(source: String) {
        #expect(defaultStatement(for: source) == nil)
    }

    @Test("Parenthesized and attributed wrappers are looked through")
    func wrappersAreUnwrapped() {
        #expect(defaultStatement(for: "([Int])") == "return []")
        #expect(defaultStatement(for: "(Int?)") == "return nil")
    }
}
