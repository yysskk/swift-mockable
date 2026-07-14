import SwiftSyntax
import SwiftSyntaxBuilder
import Testing

@testable import MockableMacros

@Suite("SwiftSyntax Compatibility Tests")
struct SwiftSyntaxCompatibilityTests {
    private func effectSpecifiers(of decl: DeclSyntax) -> FunctionEffectSpecifiersSyntax? {
        decl.as(FunctionDeclSyntax.self)?.signature.effectSpecifiers
    }

    private func accessorEffectSpecifiers(of decl: DeclSyntax) -> AccessorEffectSpecifiersSyntax? {
        guard
            let binding = decl.as(VariableDeclSyntax.self)?.bindings.first,
            case .accessors(let accessors) = binding.accessorBlock?.accessors
        else {
            return nil
        }
        return accessors.first?.effectSpecifiers
    }

    // MARK: - FunctionEffectSpecifiersSyntax

    @Test("hasThrowsEffect is true for a throwing function")
    func functionHasThrowsEffect() {
        let decl: DeclSyntax = "func fetch() throws -> Int { 0 }"
        #expect(effectSpecifiers(of: decl)?.hasThrowsEffect == true)
    }

    @Test("hasThrowsEffect is false for an async-only function")
    func asyncOnlyFunctionHasNoThrowsEffect() {
        let decl: DeclSyntax = "func fetch() async -> Int { 0 }"
        #expect(effectSpecifiers(of: decl)?.hasThrowsEffect == false)
    }

    @Test("isRethrows is true for a rethrows function")
    func rethrowsFunctionIsRethrows() {
        let decl: DeclSyntax = "func run(_ body: () throws -> Void) rethrows {}"
        #expect(effectSpecifiers(of: decl)?.isRethrows == true)
    }

    @Test("isRethrows is false for a plain throwing function")
    func throwingFunctionIsNotRethrows() {
        let decl: DeclSyntax = "func fetch() throws -> Int { 0 }"
        #expect(effectSpecifiers(of: decl)?.isRethrows == false)
    }

    @Test("throwsErrorType is the declared type for typed throws")
    func typedThrowsErrorType() {
        let decl: DeclSyntax = "func fetch() throws(FetchError) -> Int { 0 }"
        #expect(effectSpecifiers(of: decl)?.throwsErrorType?.trimmedDescription == "FetchError")
    }

    @Test("throwsErrorType is nil for untyped throws")
    func untypedThrowsHasNoErrorType() {
        let decl: DeclSyntax = "func fetch() throws -> Int { 0 }"
        #expect(effectSpecifiers(of: decl)?.throwsErrorType == nil)
    }

    // MARK: - TypeEffectSpecifiersSyntax

    @Test("hasThrowsEffect is true for a throwing function type")
    func functionTypeHasThrowsEffect() {
        let type: TypeSyntax = "() throws -> Void"
        let specifiers = type.as(FunctionTypeSyntax.self)?.effectSpecifiers
        #expect(specifiers?.hasThrowsEffect == true)
    }

    // MARK: - AccessorEffectSpecifiersSyntax

    @Test("hasThrowsEffect is true for a throwing accessor")
    func accessorHasThrowsEffect() {
        let decl: DeclSyntax = "var value: Int { get throws { 0 } }"
        #expect(accessorEffectSpecifiers(of: decl)?.hasThrowsEffect == true)
    }

    // MARK: - GenericArgumentSyntax

    @Test("makeGenericArgument wraps the given type")
    func makeGenericArgumentWrapsType() {
        let argument = makeGenericArgument(type: "Int")
        #expect(argument.trimmedDescription == "Int")
    }

    @Test("extractType returns the type of a type argument")
    func extractTypeReturnsType() {
        let argument = makeGenericArgument(type: "String")
        #expect(extractType(from: argument)?.trimmedDescription == "String")
    }

    @Test("extractType is nil for a value generic argument")
    func extractTypeIsNilForExpressionArgument() {
        // `.expr` is public API in the swift-syntax version this package resolves,
        // even though the shim itself avoids naming it (it is @_spi in 601).
        let argument = GenericArgumentSyntax(argument: .expr("3"))
        #expect(extractType(from: argument) == nil)
    }

    @Test("extractType round-trips through a parsed generic clause")
    func extractTypeFromParsedGenericClause() {
        let type: TypeSyntax = "Dictionary<String, Int>"
        let arguments = type.as(IdentifierTypeSyntax.self)?.genericArgumentClause?.arguments
        let extracted = arguments.map { $0.compactMap(extractType(from:)) } ?? []
        #expect(extracted.map(\.trimmedDescription) == ["String", "Int"])
    }

    @Test("genericArgumentsContainType finds a matching argument")
    func genericArgumentsContainMatchingType() {
        let type: TypeSyntax = "Dictionary<String, Int>"
        let arguments = type.as(IdentifierTypeSyntax.self)?.genericArgumentClause?.arguments
        #expect(arguments != nil)
        guard let arguments else {
            return
        }
        #expect(genericArgumentsContainType(arguments) { $0.trimmedDescription == "Int" })
        #expect(!genericArgumentsContainType(arguments) { $0.trimmedDescription == "Double" })
    }

    // MARK: - AttributedTypeSyntax

    @Test("hasSpecifiers is true for an inout type")
    func inoutTypeHasSpecifiers() {
        let type: TypeSyntax = "inout Int"
        #expect(type.as(AttributedTypeSyntax.self)?.hasSpecifiers == true)
    }

    @Test("hasSpecifiers is false for an attribute-only type")
    func attributeOnlyTypeHasNoSpecifiers() {
        let type: TypeSyntax = "@escaping () -> Void"
        #expect(type.as(AttributedTypeSyntax.self)?.hasSpecifiers == false)
    }

    @Test("makeAttributedType keeps the original specifiers")
    func makeAttributedTypeKeepsSpecifiers() {
        let original: TypeSyntax = "inout Int"
        let template: TypeSyntax = "@Sendable () -> Void"
        guard
            let originalType = original.as(AttributedTypeSyntax.self),
            let attributes = template.as(AttributedTypeSyntax.self)?.attributes
        else {
            Issue.record("Expected attributed types")
            return
        }
        let rebuilt = AttributedTypeSyntax.makeAttributedType(
            from: originalType,
            attributes: attributes,
            baseType: "String"
        )
        #expect(rebuilt.trimmedDescription.hasPrefix("inout"))
        #expect(rebuilt.attributes.trimmedDescription == "@Sendable")
        #expect(rebuilt.baseType.trimmedDescription == "String")
    }
}
