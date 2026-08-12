import SwiftSyntax

// MARK: - Swift-Syntax Version Compatibility

/// Provides compatibility helpers for swift-syntax API differences between versions.
/// - swift-syntax 509/510 (Swift 5.9/5.10): Uses `throwsSpecifier`, `specifier` (singular), direct type in GenericArgumentSyntax
/// - swift-syntax 600+ (Swift 6.x): Uses `throwsClause`, `specifiers` (plural)
/// - swift-syntax 601+: `GenericArgumentSyntax.argument` is an enum (`.type(...)`; `.expr` is public only in 602+)
///
/// SwiftSyntax provides empty marker modules (e.g., SwiftSyntax509, SwiftSyntax600) for version detection.

extension FunctionEffectSpecifiersSyntax {
    /// Returns whether the function has a throws effect, compatible across swift-syntax versions.
    /// A `throws(Never)` clause declares a function that cannot throw, so it reports `false`.
    var hasThrowsEffect: Bool {
        #if canImport(SwiftSyntax600)
        guard let throwsClause else {
            return false
        }
        return throwsClause.type?.isNeverType != true
        #else
        return throwsSpecifier != nil
        #endif
    }

    /// Returns whether the throws effect is `rethrows`, compatible across swift-syntax versions.
    var isRethrows: Bool {
        #if canImport(SwiftSyntax600)
        return throwsClause?.throwsSpecifier.tokenKind == .keyword(.rethrows)
        #else
        return throwsSpecifier?.tokenKind == .keyword(.rethrows)
        #endif
    }

    /// The typed-throws error type (`throws(MyError)`), or `nil` when the requirement throws
    /// nothing more specific than untyped `throws` already does: absent throws, untyped throws,
    /// `throws(Never)`, and `throws(any Error)`.
    /// Typed throws (SE-0413) requires Swift 6, so this is always `nil` on swift-syntax 509/510.
    var throwsErrorType: TypeSyntax? {
        #if canImport(SwiftSyntax600)
        return throwsClause?.type?.typedThrowsErrorType
        #else
        return nil
        #endif
    }
}

extension TypeEffectSpecifiersSyntax {
    /// Returns whether the function type has a throws effect, compatible across swift-syntax versions.
    /// A `throws(Never)` clause declares a function type that cannot throw, so it reports `false`.
    var hasThrowsEffect: Bool {
        #if canImport(SwiftSyntax600)
        guard let throwsClause else {
            return false
        }
        return throwsClause.type?.isNeverType != true
        #else
        return throwsSpecifier != nil
        #endif
    }
}

extension AccessorEffectSpecifiersSyntax {
    /// Returns whether the accessor has a throws effect, compatible across swift-syntax versions.
    /// A `get throws(Never)` clause declares an accessor that cannot throw, so it reports `false`.
    var hasThrowsEffect: Bool {
        #if canImport(SwiftSyntax600)
        guard let throwsClause else {
            return false
        }
        return throwsClause.type?.isNeverType != true
        #else
        return throwsSpecifier != nil
        #endif
    }

    /// The typed-throws error type (`get throws(MyError)`), or `nil` when the accessor throws
    /// nothing more specific than untyped `throws` already does: absent throws, untyped throws,
    /// `get throws(Never)`, and `get throws(any Error)`.
    var throwsErrorType: TypeSyntax? {
        #if canImport(SwiftSyntax600)
        return throwsClause?.type?.typedThrowsErrorType
        #else
        return nil
        #endif
    }
}

#if canImport(SwiftSyntax600)
// MARK: - Typed Throws Error Types

extension TypeSyntax {
    /// The error type a typed-throws clause names, or `nil` when the clause names a type that
    /// untyped `throws` already describes: `Never` (the function cannot throw) and `any Error`
    /// (the function can throw anything).
    var typedThrowsErrorType: TypeSyntax? {
        (isNeverType || isErrorExistentialType) ? nil : self
    }

    /// Whether the type is spelled `Never`.
    ///
    /// Like the macro's other type checks, this compares spellings: a generic parameter or a
    /// type alias named `Never` is treated as `Never`.
    var isNeverType: Bool {
        ["Never", "Swift.Never"].contains(trimmedDescription)
    }

    /// Whether the type is spelled `any Error`, including the bare `Error` sugar.
    private var isErrorExistentialType: Bool {
        let constraint = self.as(SomeOrAnyTypeSyntax.self)?.constraint ?? self
        return ["Error", "Swift.Error"].contains(constraint.trimmedDescription)
    }
}
#endif

/// Creates a GenericArgumentSyntax with a type, compatible across swift-syntax versions.
func makeGenericArgument(type: TypeSyntax) -> GenericArgumentSyntax {
    #if canImport(SwiftSyntax601)
    return GenericArgumentSyntax(argument: .type(type))
    #else
    return GenericArgumentSyntax(argument: type)
    #endif
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
