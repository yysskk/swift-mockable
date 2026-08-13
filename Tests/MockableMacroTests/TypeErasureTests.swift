import SwiftSyntax
import Testing

@testable import MockableMacros

@Suite("Type Erasure Tests")
struct TypeErasureTests {
    /// Erases `source` with the given generic parameter names and returns the
    /// result formatted the way expansion output is, so assertions match the
    /// spelling that reaches generated mocks.
    private func erased(_ source: String, genericParamNames: Set<String> = []) -> String {
        let type = TypeSyntax(stringLiteral: source)
        return MockGenerator.eraseGenericTypes(in: type, genericParamNames: genericParamNames)
            .formatted()
            .description
    }

    // MARK: - Generic parameter substitution

    @Test("A bare generic parameter collapses to Any")
    func bareGenericParameter() {
        #expect(erased("T", genericParamNames: ["T"]) == "Any")
    }

    @Test("A non-generic identifier is unchanged")
    func nonGenericIdentifier() {
        #expect(erased("Int", genericParamNames: ["T"]) == "Int")
        #expect(erased("T") == "T")
    }

    @Test("An array element is erased in place")
    func arrayElement() {
        #expect(erased("[T]", genericParamNames: ["T"]) == "[Any]")
        #expect(erased("[Int]", genericParamNames: ["T"]) == "[Int]")
    }

    @Test("An optional wrapped type is erased in place")
    func optionalWrappedType() {
        #expect(erased("T?", genericParamNames: ["T"]) == "Any?")
        #expect(erased("Int?", genericParamNames: ["T"]) == "Int?")
    }

    @Test("A dictionary value is erased in place")
    func dictionaryValue() {
        #expect(erased("[String: T]", genericParamNames: ["T"]) == "[String: Any]")
        #expect(erased("[String: Int]", genericParamNames: ["T"]) == "[String: Int]")
    }

    @Test("A dictionary with a generic key collapses to Any because Any is not Hashable")
    func dictionaryGenericKey() {
        #expect(erased("[T: String]", genericParamNames: ["T"]) == "Any")
    }

    @Test("A multi-element tuple is erased element-wise")
    func tupleElements() {
        #expect(erased("(T, String)", genericParamNames: ["T"]) == "(Any, String)")
    }

    @Test("Spellings without an in-place erasure collapse to Any")
    func collapsingSpellings() {
        #expect(erased("Box<T>", genericParamNames: ["T"]) == "Any")
        #expect(erased("Box<[T]>", genericParamNames: ["T"]) == "Any")
        #expect(erased("MyModule.Box<T>", genericParamNames: ["T"]) == "Any")
        #expect(erased("T.Element", genericParamNames: ["T"]) == "Any")
        #expect(erased("T.Type", genericParamNames: ["T"]) == "Any")
        #expect(erased("any Sequence<T>", genericParamNames: ["T"]) == "Any")
    }

    @Test("A generic type applied to a non-generic argument is unchanged")
    func genericApplicationWithoutParameter() {
        #expect(erased("Box<Int>", genericParamNames: ["T"]) == "Box<Int>")
    }

    // MARK: - Normalization independent of generics

    @Test("An implicitly unwrapped optional becomes a regular optional")
    func implicitlyUnwrappedOptional() {
        #expect(erased("Int!") == "Int?")
        #expect(erased("T!", genericParamNames: ["T"]) == "Any?")
    }

    @Test("The escaping attribute is stripped outside parameter position")
    func escapingAttributeStripped() {
        #expect(erased("@escaping () -> Void") == "() -> Void")
        #expect(erased("@escaping @Sendable () -> Void") == "@Sendable () -> Void")
    }

    @Test("Parameter specifiers are stripped outside parameter position")
    func parameterSpecifiersStripped() {
        // A stored property or closure type cannot carry any of these.
        #expect(erased("inout Int") == "Int")
        #expect(erased("consuming Payload") == "Payload")
        #expect(erased("borrowing Payload") == "Payload")
        #expect(erased("sending Payload") == "Payload")
        #expect(erased("isolated any Actor") == "any Actor")
        #expect(erased("consuming Box<T>", genericParamNames: ["T"]) == "Any")
    }

    @Test("A single-element parenthesized type is unwrapped")
    func parenthesizedTypeUnwrapped() {
        #expect(erased("(Int)") == "Int")
    }

    @Test("An erased closure nested in an optional keeps its parentheses")
    func optionalClosureParenthesized() {
        #expect(erased("(() -> T)?", genericParamNames: ["T"]) == "(() -> Any)?")
        #expect(erased("(@Sendable () -> T)?", genericParamNames: ["T"]) == "(@Sendable () -> Any)?")
    }

    @Test("A closure's parameters and return type are erased")
    func closureParameterAndReturn() {
        #expect(erased("(T) -> T", genericParamNames: ["T"]) == "(Any) -> Any")
    }

    #if canImport(SwiftSyntax600)
    @Test("A typed-throws clause on a function type is erased to untyped throws")
    func typedThrowsClauseErased() {
        #expect(erased("() throws(SomeError) -> Void") == "() throws -> Void")
    }
    #endif

    // MARK: - typeContainsGeneric

    @Test("typeContainsGeneric finds a parameter at any depth")
    func containsGenericAtDepth() {
        let type = TypeSyntax(stringLiteral: "Box<[(String, T.Element)]>")
        #expect(MockGenerator.typeContainsGeneric(type, genericParamNames: ["T"]))
    }

    @Test("typeContainsGeneric is false without matching parameters")
    func containsGenericWithoutMatch() {
        let type = TypeSyntax(stringLiteral: "Box<[(String, U.Element)]>")
        #expect(!MockGenerator.typeContainsGeneric(type, genericParamNames: ["T"]))
        #expect(!MockGenerator.typeContainsGeneric(type, genericParamNames: []))
    }
}
