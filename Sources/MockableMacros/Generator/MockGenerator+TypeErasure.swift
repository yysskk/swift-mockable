import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Type Erasure

extension MockGenerator {
    /// The names of a requirement's generic parameters, e.g. `{"T", "U"}` for
    /// `func convert<T, U>(_ value: T) -> U`. Types mentioning one of these cannot be
    /// referenced from the mock's class-scope storage and handlers, so they are erased.
    static func extractGenericParameterNames(from decl: some WithGenericParametersSyntax) -> Set<String> {
        guard let genericClause = decl.genericParameterClause else {
            return []
        }
        return Set(genericClause.parameters.map { $0.name.text })
    }

    /// Erases a nested function type's typed-throws error type (`() throws(E) -> Void`) to
    /// untyped `throws`. The stored handler is always untyped-throwing, so a typed-throws
    /// function value must never be embedded in it: a generic error type would be out of the
    /// method's generic scope, and even a concrete one would require the Swift 6 runtime
    /// (typed-throws function values ship in macOS 15+).
    private static func erasedEffectSpecifiers(
        _ effects: TypeEffectSpecifiersSyntax?
    ) -> TypeEffectSpecifiersSyntax? {
        guard let effects else {
            return nil
        }
        #if canImport(SwiftSyntax600)
        guard let throwsClause = effects.throwsClause, throwsClause.type != nil else {
            return effects
        }
        let untypedThrowsClause = throwsClause
            .with(\.leftParen, nil)
            .with(\.type, nil)
            .with(\.rightParen, nil)
        return effects.with(\.throwsClause, untypedThrowsClause)
        #else
        return effects
        #endif
    }

    /// Erases generic parameters (to `Any`) and normalizes nested types so a
    /// requirement's types can be embedded in stored properties and handler closures.
    ///
    /// The categories are tried in a fixed order. Attributed types, tuples, implicitly
    /// unwrapped optionals, and function types are normalized even when the declaration
    /// is non-generic — they strip `@escaping`, unwrap parentheses, rewrite `T!` to `T?`,
    /// and erase typed-throws clauses, all of which are required regardless of generics.
    /// The remaining categories only substitute generic parameters, so they are skipped
    /// entirely when `genericParamNames` is empty.
    static func eraseGenericTypes(in type: TypeSyntax, genericParamNames: Set<String>) -> TypeSyntax {
        if let attributedType = type.as(AttributedTypeSyntax.self) {
            return eraseAttributedType(attributedType, genericParamNames: genericParamNames)
        }
        if let tupleType = type.as(TupleTypeSyntax.self),
           let erased = eraseTupleType(tupleType, genericParamNames: genericParamNames) {
            return erased
        }
        if let implicitOptional = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return eraseImplicitlyUnwrappedOptionalType(implicitOptional, genericParamNames: genericParamNames)
        }
        if let funcType = type.as(FunctionTypeSyntax.self) {
            return eraseFunctionType(funcType, genericParamNames: genericParamNames)
        }

        // The remaining categories only substitute generic parameters, so there is
        // nothing to erase when the enclosing declaration is non-generic.
        if genericParamNames.isEmpty {
            return type
        }

        if let optionalType = type.as(OptionalTypeSyntax.self),
           let erased = eraseOptionalType(optionalType, genericParamNames: genericParamNames) {
            return erased
        }
        if let arrayType = type.as(ArrayTypeSyntax.self),
           let erased = eraseArrayType(arrayType, genericParamNames: genericParamNames) {
            return erased
        }
        if let dictionaryType = type.as(DictionaryTypeSyntax.self),
           let erased = eraseDictionaryType(dictionaryType, genericParamNames: genericParamNames) {
            return erased
        }

        // Every other spelling that mentions a generic parameter — a bare parameter (`T`),
        // a generic type applied to one (`Box<[T]>`), a qualified or nested spelling
        // (`MyModule.Box<T>`, `T.Element`), an existential (`any Sequence<T>`), a metatype
        // (`T.Type`) — has no in-place erasure: rewriting `Box<T>` to `Box<Any>` would
        // require `Box` to accept `Any`, which its own constraints may forbid. Collapse it.
        if typeContainsGeneric(type, genericParamNames: genericParamNames) {
            return TypeSyntax(stringLiteral: "Any")
        }

        return type
    }

    /// Strips `@escaping` and every parameter specifier — both invalid outside parameter
    /// position — and recurses into the base type, e.g. `@escaping @Sendable (Event) -> Void`
    /// or `consuming Payload`. Runs regardless of `genericParamNames`, so a non-generic
    /// parameter is normalized for storage too.
    ///
    /// An `inout` parameter loses its specifier here like any other; the witness keeps the
    /// requirement's own signature, and the write-back machinery reintroduces the mutation
    /// separately (see `MockGenerator+Function`).
    private static func eraseAttributedType(
        _ attributedType: AttributedTypeSyntax,
        genericParamNames: Set<String>
    ) -> TypeSyntax {
        let filteredAttributes = stripEscapingAttribute(from: attributedType.attributes)
        let processedBaseType = eraseGenericTypes(in: attributedType.baseType, genericParamNames: genericParamNames)

        if filteredAttributes.isEmpty {
            return processedBaseType
        }

        return TypeSyntax(AttributedTypeSyntax.makeUnspecifiedAttributedType(
            attributes: filteredAttributes,
            baseType: processedBaseType
        ))
    }

    /// The type as it is written without its parameter specifiers, e.g. `inout Int!` ->
    /// `Int!`. This is the type the requirement actually deals in, and what the erased
    /// storage type and the write-back cast are both derived from.
    static func unspecifiedType(_ type: TypeSyntax) -> TypeSyntax {
        guard let attributedType = type.as(AttributedTypeSyntax.self), attributedType.hasSpecifiers else {
            return type
        }
        if attributedType.attributes.isEmpty {
            return attributedType.baseType.trimmed
        }
        return TypeSyntax(AttributedTypeSyntax.makeUnspecifiedAttributedType(
            attributes: attributedType.attributes,
            baseType: attributedType.baseType
        ))
    }

    /// The parameter specifiers a type carries, e.g. `["inout"]`, or an empty array.
    static func specifiers(of type: TypeSyntax) -> [String] {
        type.as(AttributedTypeSyntax.self)?.specifierTexts ?? []
    }

    /// Erases a tuple type. A single-element unlabeled tuple is a parenthesized type
    /// (e.g. `(@escaping (Error?) -> Void)`) and is unwrapped so the inner type is
    /// processed — this runs even when non-generic. A multi-element tuple only needs
    /// erasure when generic parameters are present; otherwise `nil` tells the caller
    /// to leave it unchanged.
    private static func eraseTupleType(
        _ tupleType: TupleTypeSyntax,
        genericParamNames: Set<String>
    ) -> TypeSyntax? {
        if tupleType.elements.count == 1, let element = tupleType.elements.first,
           element.firstName == nil, element.secondName == nil {
            return eraseGenericTypes(in: element.type, genericParamNames: genericParamNames)
        }
        guard !genericParamNames.isEmpty else {
            return nil
        }
        let processedElements = TupleTypeElementListSyntax(
            tupleType.elements.map { element in
                TupleTypeElementSyntax(
                    firstName: element.firstName,
                    secondName: element.secondName,
                    colon: element.colon,
                    type: eraseGenericTypes(in: element.type, genericParamNames: genericParamNames),
                    ellipsis: element.ellipsis,
                    trailingComma: element.trailingComma
                )
            }
        )
        return TypeSyntax(TupleTypeSyntax(
            leftParen: tupleType.leftParen,
            elements: processedElements,
            rightParen: tupleType.rightParen
        ))
    }

    /// Converts an implicitly unwrapped optional `T!` to a regular optional `T?`
    /// (erasing `T`). `T!` is rejected in nested positions such as a handler closure
    /// type (`(@Sendable () -> T!)?` does not compile), so this runs even when non-generic.
    private static func eraseImplicitlyUnwrappedOptionalType(
        _ implicitOptional: ImplicitlyUnwrappedOptionalTypeSyntax,
        genericParamNames: Set<String>
    ) -> TypeSyntax {
        let erasedWrapped = eraseGenericTypes(in: implicitOptional.wrappedType, genericParamNames: genericParamNames)
        return TypeSyntax(OptionalTypeSyntax(wrappedType: parenthesized(erasedWrapped)))
    }

    /// Parenthesizes a function type so it can be wrapped in an optional: `(() -> Any)?`
    /// rather than `() -> Any?`, which parses as a function returning an optional. Other
    /// types are returned unchanged — erasure never produces another spelling that binds
    /// more loosely than `?`, since existentials and compositions collapse to `Any`.
    private static func parenthesized(_ type: TypeSyntax) -> TypeSyntax {
        guard isFunctionType(type) else {
            return type
        }
        return TypeSyntax(TupleTypeSyntax(
            elements: TupleTypeElementListSyntax([TupleTypeElementSyntax(type: type)])
        ))
    }

    /// Whether `type` is a function type, looking through attributes so a closure that keeps
    /// one — `@Sendable () -> Any` — is recognized as needing the same parentheses as a bare
    /// one. The attributes stay inside the parentheses, where they belong.
    private static func isFunctionType(_ type: TypeSyntax) -> Bool {
        if let attributedType = type.as(AttributedTypeSyntax.self) {
            return isFunctionType(attributedType.baseType)
        }
        return type.is(FunctionTypeSyntax.self)
    }

    /// Erases a function (closure) type: recurses into every parameter and the return
    /// type, and rewrites a typed-throws clause to untyped `throws` (the stored handler
    /// is always untyped-throwing). Runs even when non-generic so the throws erasure applies.
    private static func eraseFunctionType(
        _ funcType: FunctionTypeSyntax,
        genericParamNames: Set<String>
    ) -> TypeSyntax {
        let processedParameters = TupleTypeElementListSyntax(
            funcType.parameters.map { param in
                TupleTypeElementSyntax(
                    firstName: param.firstName,
                    secondName: param.secondName,
                    colon: param.colon,
                    type: eraseGenericTypes(in: param.type, genericParamNames: genericParamNames),
                    ellipsis: param.ellipsis,
                    trailingComma: param.trailingComma
                )
            }
        )

        let processedReturnType = eraseGenericTypes(
            in: funcType.returnClause.type,
            genericParamNames: genericParamNames
        )

        return TypeSyntax(FunctionTypeSyntax(
            leftParen: funcType.leftParen,
            parameters: processedParameters,
            rightParen: funcType.rightParen,
            effectSpecifiers: erasedEffectSpecifiers(funcType.effectSpecifiers),
            returnClause: ReturnClauseSyntax(
                arrow: funcType.returnClause.arrow,
                type: processedReturnType
            )
        ))
    }

    /// Erases the wrapped type of an optional `T?`, returning a new optional only when
    /// the wrapped type actually changed (otherwise `nil` to leave it unchanged).
    private static func eraseOptionalType(
        _ optionalType: OptionalTypeSyntax,
        genericParamNames: Set<String>
    ) -> TypeSyntax? {
        let erasedWrapped = eraseGenericTypes(in: optionalType.wrappedType, genericParamNames: genericParamNames)
        guard erasedWrapped.description != optionalType.wrappedType.description else {
            return nil
        }
        return TypeSyntax(OptionalTypeSyntax(wrappedType: parenthesized(erasedWrapped)))
    }

    /// Erases the element type of an array `[T]`, returning a new array only when the
    /// element type actually changed (otherwise `nil` to leave it unchanged).
    private static func eraseArrayType(
        _ arrayType: ArrayTypeSyntax,
        genericParamNames: Set<String>
    ) -> TypeSyntax? {
        let erasedElement = eraseGenericTypes(in: arrayType.element, genericParamNames: genericParamNames)
        guard erasedElement.description != arrayType.element.description else {
            return nil
        }
        return TypeSyntax(ArrayTypeSyntax(element: erasedElement))
    }

    /// Erases the value type of a dictionary `[String: T]`, returning a new dictionary only
    /// when the value type actually changed (otherwise `nil` to leave it unchanged).
    /// A key that mentions a generic parameter cannot be erased in place — `Any` is not
    /// `Hashable`, so `[Any: String]` would not compile — so the whole dictionary collapses
    /// to `Any`, matching how the unsugared `Dictionary<T, String>` spelling is erased.
    private static func eraseDictionaryType(
        _ dictionaryType: DictionaryTypeSyntax,
        genericParamNames: Set<String>
    ) -> TypeSyntax? {
        if typeContainsGeneric(dictionaryType.key, genericParamNames: genericParamNames) {
            return TypeSyntax(stringLiteral: "Any")
        }
        let erasedValue = eraseGenericTypes(in: dictionaryType.value, genericParamNames: genericParamNames)
        guard erasedValue.description != dictionaryType.value.description else {
            return nil
        }
        return TypeSyntax(DictionaryTypeSyntax(key: dictionaryType.key, value: erasedValue))
    }

    /// Strips the @escaping attribute from an AttributeListSyntax.
    /// @escaping is only valid in function parameter position, not in property types.
    private static func stripEscapingAttribute(from attributes: AttributeListSyntax) -> AttributeListSyntax {
        let filteredAttributes = attributes.filter { element in
            switch element {
            case .attribute(let attr):
                return attr.attributeName.trimmedDescription != "escaping"
            case .ifConfigDecl:
                return true
            }
        }
        return filteredAttributes
    }

    /// Whether `type` mentions one of the enclosing declaration's generic parameters, and so
    /// cannot be referenced from the mock's class-scope storage and handlers. This is the
    /// single source of truth for erasure: `eraseGenericTypes` erases exactly the types this
    /// reports, and the generated method casts its result back when the return type is one.
    static func typeContainsGeneric(_ type: TypeSyntax, genericParamNames: Set<String>) -> Bool {
        if genericParamNames.isEmpty {
            return false
        }
        return mentionsGenericParameter(Syntax(type), genericParamNames: genericParamNames)
    }

    /// Searches a type for an identifier naming a generic parameter.
    ///
    /// Walking the syntax tree covers every spelling at any depth — `Box<[T]>`, `(T, String)`,
    /// `() -> T`, `T.Element`, `any Sequence<T>`, `T.Type` — where enumerating type kinds
    /// silently misses whichever one it forgets. Matching `IdentifierTypeSyntax` rather than
    /// raw tokens keeps a name that merely spells a parameter without referring to it, such
    /// as a tuple element label or the member name in `Container.T`, from counting.
    private static func mentionsGenericParameter(
        _ node: Syntax,
        genericParamNames: Set<String>
    ) -> Bool {
        if let identifierType = node.as(IdentifierTypeSyntax.self),
           genericParamNames.contains(identifierType.name.text) {
            return true
        }
        return node.children(viewMode: .sourceAccurate).contains { child in
            mentionsGenericParameter(child, genericParamNames: genericParamNames)
        }
    }

    /// The spelling used as the target of the `as!` that casts an erased handler result back
    /// to a requirement's return type. An implicitly unwrapped optional cannot appear in a
    /// cast — `as! T!` is rejected with "using '!' is not allowed here" — so it is written as
    /// a regular optional, which converts back to `T!` at the return.
    static func castTargetType(for returnType: TypeSyntax) -> String {
        guard let implicitOptional = returnType.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) else {
            return returnType.description
        }
        return OptionalTypeSyntax(wrappedType: implicitOptional.wrappedType.trimmed).description
    }

    /// Whether the mock can cast an erased handler result back to `returnType`.
    ///
    /// The cast rebuilds the types that erasure rebuilt in place, but the Swift runtime
    /// cannot convert between function types, so a closure erased to `(Any) -> Void` can
    /// never be cast back to `(T) -> Void`.
    static func erasedResultCanBeCast(to returnType: TypeSyntax, genericParamNames: Set<String>) -> Bool {
        functionTypesErasedInPlace(in: returnType, genericParamNames: genericParamNames) { functionType in
            !typeContainsGeneric(TypeSyntax(functionType), genericParamNames: genericParamNames)
        }
    }

    /// Whether an argument can be forwarded to the erased handler parameter for `parameterType`.
    ///
    /// A closure's own parameters are contravariant, so erasing them widens the type in the
    /// unusable direction: `(T) -> Void` cannot be passed where `(Any) -> Void` is expected.
    /// Erasing a closure's *result* is fine, since `() -> T` can be passed as `() -> Any`.
    static func erasedArgumentCanBeForwarded(for parameterType: TypeSyntax, genericParamNames: Set<String>) -> Bool {
        functionTypesErasedInPlace(in: parameterType, genericParamNames: genericParamNames) { functionType in
            !functionType.parameters.contains { parameter in
                typeContainsGeneric(parameter.type, genericParamNames: genericParamNames)
            }
        }
    }

    /// Whether every function type that erasure rebuilds in place satisfies `isSupported`.
    ///
    /// Only the positions erasure rebuilds are visited — optionals, arrays, dictionary values,
    /// tuples, and other function types. A function type inside a nominal type
    /// (`Box<() -> T>`) is not reached, because that type erases to `Any` as a whole and is
    /// forwarded and cast back as one value.
    private static func functionTypesErasedInPlace(
        in type: TypeSyntax,
        genericParamNames: Set<String>,
        allSatisfy isSupported: (FunctionTypeSyntax) -> Bool
    ) -> Bool {
        func recurse(into nested: TypeSyntax) -> Bool {
            functionTypesErasedInPlace(in: nested, genericParamNames: genericParamNames, allSatisfy: isSupported)
        }

        if let attributedType = type.as(AttributedTypeSyntax.self) {
            return recurse(into: attributedType.baseType)
        }
        if let functionType = type.as(FunctionTypeSyntax.self) {
            guard isSupported(functionType) else {
                return false
            }
            return functionType.parameters.allSatisfy { recurse(into: $0.type) }
                && recurse(into: functionType.returnClause.type)
        }
        if let tupleType = type.as(TupleTypeSyntax.self) {
            return tupleType.elements.allSatisfy { recurse(into: $0.type) }
        }
        if let optionalType = type.as(OptionalTypeSyntax.self) {
            return recurse(into: optionalType.wrappedType)
        }
        if let implicitOptional = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return recurse(into: implicitOptional.wrappedType)
        }
        if let arrayType = type.as(ArrayTypeSyntax.self) {
            return recurse(into: arrayType.element)
        }
        if let dictionaryType = type.as(DictionaryTypeSyntax.self) {
            // A key mentioning a generic parameter erases the dictionary as a whole, so
            // nothing inside it is rebuilt in place.
            if typeContainsGeneric(dictionaryType.key, genericParamNames: genericParamNames) {
                return true
            }
            return recurse(into: dictionaryType.value)
        }
        return true
    }
}
