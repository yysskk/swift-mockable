import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Associated Type Generation

extension MockGenerator {
    /// The type aliases the mock needs to satisfy the protocol's `associatedtype` and
    /// `typealias` declarations. Emitted first so later members can refer to them.
    func generateAssociatedTypeMembers() -> [MemberBlockItemSyntax] {
        mapMemberBlockItemsPreservingIfConfig { decl in
            if let associatedType = decl.as(AssociatedTypeDeclSyntax.self) {
                return [MemberBlockItemSyntax(decl: generateTypeAlias(for: associatedType))]
            }

            if let typeAliasDecl = decl.as(TypeAliasDeclSyntax.self) {
                // A generic alias names its parameters in its own clause, and any
                // constraint on them lives in the `where` clause, so both have to come
                // along or the alias no longer describes the same type.
                let rebuilt = TypeAliasDeclSyntax(
                    modifiers: buildModifiers(),
                    name: .identifier(typeAliasDecl.name.text),
                    genericParameterClause: typeAliasDecl.genericParameterClause?.trimmed,
                    initializer: TypeInitializerClauseSyntax(
                        equal: .equalToken(leadingTrivia: .space, trailingTrivia: .space),
                        value: typeAliasDecl.initializer.value
                    ),
                    genericWhereClause: typeAliasDecl.genericWhereClause?.trimmed
                )
                return [MemberBlockItemSyntax(decl: rebuilt)]
            }

            return []
        }
    }

    /// Generates a typealias declaration for an associated type.
    /// Uses the default type if specified, otherwise falls back to Any.
    func generateTypeAlias(for associatedType: AssociatedTypeDeclSyntax) -> TypeAliasDeclSyntax {
        let name = associatedType.name.text

        // Determine the concrete type:
        // 1. If the associated type has a default type (= SomeType), use it
        // 2. Otherwise, use Any as a fallback
        let concreteType: TypeSyntax
        if let initializer = associatedType.initializer {
            concreteType = initializer.value
        } else {
            concreteType = TypeSyntax(stringLiteral: "Any")
        }

        return TypeAliasDeclSyntax(
            modifiers: buildModifiers(),
            name: .identifier(name),
            initializer: TypeInitializerClauseSyntax(
                equal: .equalToken(leadingTrivia: .space, trailingTrivia: .space),
                value: concreteType
            )
        )
    }
}
