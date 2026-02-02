import SwiftSyntax

// MARK: - Swift-Syntax Version Compatibility

/// Provides compatibility helpers for swift-syntax API differences between versions.
/// - swift-syntax 509/510 (Swift 5.9/5.10): Uses `throwsSpecifier`, `specifier` (singular), direct type in GenericArgumentSyntax
/// - swift-syntax 600+ (Swift 6.x): Uses `throwsClause`, `specifiers` (plural), `GenericArgumentSyntax(argument: .type(...))`
///
/// SwiftSyntax provides empty marker modules (e.g., SwiftSyntax509, SwiftSyntax600) for version detection.

extension FunctionEffectSpecifiersSyntax {
    /// Returns whether the function has a throws effect, compatible across swift-syntax versions.
    var hasThrowsEffect: Bool {
        #if canImport(SwiftSyntax600)
        return throwsClause != nil
        #else
        return throwsSpecifier != nil
        #endif
    }
}

/// Creates a GenericArgumentSyntax with a type, compatible across swift-syntax versions.
func makeGenericArgument(type: TypeSyntax) -> GenericArgumentSyntax {
    #if canImport(SwiftSyntax600)
    return GenericArgumentSyntax(argument: .type(type))
    #else
    return GenericArgumentSyntax(argument: type)
    #endif
}

/// Extracts the type from a GenericArgumentSyntax, compatible across swift-syntax versions.
func extractType(from argument: GenericArgumentSyntax) -> TypeSyntax? {
    #if canImport(SwiftSyntax600)
    switch argument.argument {
    case .type(let typeSyntax):
        return typeSyntax
    case .expr:
        return nil
    }
    #else
    return argument.argument
    #endif
}

/// Checks if GenericArgumentListSyntax contains any type matching the predicate.
func genericArgumentsContainType(
    _ arguments: GenericArgumentListSyntax,
    where predicate: (TypeSyntax) -> Bool
) -> Bool {
    for arg in arguments {
        if let typeSyntax = extractType(from: arg), predicate(typeSyntax) {
            return true
        }
    }
    return false
}

// MARK: - AttributedTypeSyntax Compatibility

extension AttributedTypeSyntax {
    /// Returns whether the type has any specifiers, compatible across swift-syntax versions.
    var hasSpecifiers: Bool {
        #if canImport(SwiftSyntax600)
        return !specifiers.isEmpty
        #else
        return specifier != nil
        #endif
    }

    /// Creates a new AttributedTypeSyntax with the given attributes and base type.
    static func makeAttributedType(
        from original: AttributedTypeSyntax,
        attributes: AttributeListSyntax,
        baseType: TypeSyntax
    ) -> AttributedTypeSyntax {
        #if canImport(SwiftSyntax600)
        return AttributedTypeSyntax(
            specifiers: original.specifiers,
            attributes: attributes,
            baseType: baseType
        )
        #else
        return AttributedTypeSyntax(
            specifier: original.specifier,
            attributes: attributes,
            baseType: baseType
        )
        #endif
    }
}
