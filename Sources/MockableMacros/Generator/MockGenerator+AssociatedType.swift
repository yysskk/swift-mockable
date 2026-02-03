import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Associated Type Generation

extension MockGenerator {
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
