import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Default Return Values

/// Decides what a witness returns when its handler is unset: the return type's
/// natural empty value where it has one, or nothing for a `Void` return.
///
/// Stateless: it reads syntax only, never the generator's state.
enum DefaultReturnValue {
    /// Returns the statement to place inside the `else` branch of the unset-handler guard
    /// when the return type has a natural empty default: optionals return `nil`, arrays and
    /// sets return `[]`, dictionaries return `[:]`. Returns `nil` for types without a natural
    /// default, signaling the caller to fall back to `fatalError`.
    static func defaultReturnStatement(for returnType: TypeSyntax?) -> String? {
        guard let returnType else {
            return nil
        }
        let type = unwrapForDefaultDetection(returnType)
        // Check optional first so wrappers like `[Foo]?` or `Set<T>?` return nil rather than [].
        if isOptionalType(type) {
            return "return nil"
        }
        if isArrayType(type) || isSetType(type) {
            return "return []"
        }
        if isDictionaryType(type) {
            return "return [:]"
        }
        return nil
    }

    /// Strips single-element tuples (parenthesized types) and attributed wrappers so the
    /// underlying type can be classified, mirroring the dispatch precedence of `eraseGenericTypes`.
    static func unwrapForDefaultDetection(_ type: TypeSyntax) -> TypeSyntax {
        if let attributedType = type.as(AttributedTypeSyntax.self) {
            return unwrapForDefaultDetection(attributedType.baseType)
        }
        if let tupleType = type.as(TupleTypeSyntax.self),
           tupleType.elements.count == 1,
           let element = tupleType.elements.first,
           element.firstName == nil, element.secondName == nil {
            return unwrapForDefaultDetection(element.type)
        }
        return type
    }

    /// `T?`, `T!`, or the unsugared `Optional<T>`.
    private static func isOptionalType(_ type: TypeSyntax) -> Bool {
        if type.is(OptionalTypeSyntax.self) || type.is(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return true
        }
        return isGenericStdlibType(type, named: "Optional")
    }

    /// `[T]` or the unsugared `Array<T>`.
    private static func isArrayType(_ type: TypeSyntax) -> Bool {
        if type.is(ArrayTypeSyntax.self) {
            return true
        }
        return isGenericStdlibType(type, named: "Array")
    }

    /// `Set<T>`, which has no sugared spelling.
    private static func isSetType(_ type: TypeSyntax) -> Bool {
        isGenericStdlibType(type, named: "Set")
    }

    /// `[K: V]` or the unsugared `Dictionary<K, V>`.
    private static func isDictionaryType(_ type: TypeSyntax) -> Bool {
        if type.is(DictionaryTypeSyntax.self) {
            return true
        }
        return isGenericStdlibType(type, named: "Dictionary")
    }

    /// True when `type` is an identifier with a generic argument clause and the given name,
    /// e.g. `Optional<Foo>`, `Array<Foo>`, `Set<Foo>`, `Dictionary<K, V>`,
    /// or the module-qualified form `Swift.Optional<Foo>`, `Swift.Array<Foo>`, etc.
    private static func isGenericStdlibType(_ type: TypeSyntax, named name: String) -> Bool {
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return identifier.name.text == name && identifier.genericArgumentClause != nil
        }
        if let member = type.as(MemberTypeSyntax.self) {
            return member.name.text == name && member.genericArgumentClause != nil
        }
        return false
    }

    /// Whether a return type is something other than `Void`, however it is spelled:
    /// `Void`, `()`, `Swift.Void`, and any of them parenthesized all mean the same
    /// thing, and a requirement returning nothing has to be mocked the same way for
    /// each — otherwise `-> Swift.Void` traps on an unset handler where the identical
    /// `-> Void` no-ops.
    static func returnsAValue(_ returnType: TypeSyntax) -> Bool {
        let trimmed = unwrapForDefaultDetection(returnType).trimmedDescription
        return trimmed != "Void" && trimmed != "Swift.Void" && trimmed != "()"
    }
}
