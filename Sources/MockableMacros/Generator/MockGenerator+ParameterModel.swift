import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Parameter Model

extension MockGenerator {
    /// The parameters that can be recorded in `CallArgs`. Non-escaping closure
    /// parameters are excluded because a non-escaping value cannot be stored; the
    /// call is still counted and the closure is still forwarded to the handler.
    static func storableParameters(_ parameters: FunctionParameterListSyntax) -> FunctionParameterListSyntax {
        FunctionParameterListSyntax(parameters.filter { !isNonEscapingClosureParameter($0) })
    }

    /// The element type of the `CallArgs` array, built from the storable parameters only.
    static func buildCallArgsTupleType(
        parameters: FunctionParameterListSyntax,
        genericParamNames: Set<String> = []
    ) -> TypeSyntax {
        buildParameterTupleType(parameters: storableParameters(parameters), genericParamNames: genericParamNames)
    }

    /// The value appended to `CallArgs`, built from the storable parameters only.
    static func buildCallArgsExpression(parameters: FunctionParameterListSyntax) -> ExprSyntax {
        buildArgsExpression(parameters: storableParameters(parameters))
    }

    /// Whether a parameter is a non-escaping closure that cannot be stored in `CallArgs`.
    /// Escaping, optional, `@autoclosure`, and variadic closures are all storable and
    /// therefore excluded from this check.
    static func isNonEscapingClosureParameter(_ param: FunctionParameterSyntax) -> Bool {
        guard param.ellipsis == nil else {
            return false
        }
        return isNonEscapingClosureType(param.type)
    }

    /// Whether a type is a closure that Swift treats as non-escaping in parameter
    /// position, looking through parentheses and attributes.
    private static func isNonEscapingClosureType(_ type: TypeSyntax) -> Bool {
        // Unwrap a single-element parenthesizing tuple, e.g. `(@escaping () -> Void)`.
        if let tupleType = type.as(TupleTypeSyntax.self),
           tupleType.elements.count == 1, let element = tupleType.elements.first,
           element.firstName == nil, element.secondName == nil {
            return isNonEscapingClosureType(element.type)
        }
        if let attributedType = type.as(AttributedTypeSyntax.self) {
            let attributeNames = attributedType.attributes.compactMap { element -> String? in
                if case .attribute(let attribute) = element {
                    return attribute.attributeName.trimmedDescription
                }
                return nil
            }
            // `@escaping` closures are storable; `@autoclosure` is evaluated separately.
            if attributeNames.contains("escaping") || attributeNames.contains("autoclosure") {
                return false
            }
            return attributedType.baseType.is(FunctionTypeSyntax.self)
        }
        return type.is(FunctionTypeSyntax.self)
    }

    /// The element type of the `CallArgs` array: an empty tuple for no parameters, the
    /// bare storage type for one, and a labeled tuple (`(a: Int, b: String)`) for several,
    /// so recorded calls keep their argument labels.
    static func buildParameterTupleType(
        parameters: FunctionParameterListSyntax,
        genericParamNames: Set<String> = []
    ) -> TypeSyntax {
        if parameters.isEmpty {
            return TypeSyntax(TupleTypeSyntax(elements: TupleTypeElementListSyntax([])))
        }

        if parameters.count == 1, let param = parameters.first {
            return parameterStorageType(for: param, genericParamNames: genericParamNames)
        }

        let tupleElements = parameters.enumerated().map { index, param -> TupleTypeElementSyntax in
            let isLast = index == parameters.count - 1
            let erasedType = parameterStorageType(for: param, genericParamNames: genericParamNames)
            return TupleTypeElementSyntax(
                firstName: MockGenerator.recordedArgumentLabel(of: param),
                colon: .colonToken(trailingTrivia: .space),
                type: erasedType,
                trailingComma: isLast ? nil : .commaToken(trailingTrivia: .space)
            )
        }

        return TypeSyntax(TupleTypeSyntax(elements: TupleTypeElementListSyntax(tupleElements)))
    }

    /// Builds a comma-joined, label-less list of the per-parameter storage types,
    /// e.g. for `(a: Int, b: Int)` returns `"Int, Int"`. Reuses `parameterStorageType`
    /// so the erasure (inout stripped, variadic `T...` -> `[T]`, generics -> `Any`,
    /// `@escaping` stripped, `T!` -> `T?`) matches the labeled-tuple element types exactly.
    static func buildSeparateParameterTypeList(
        parameters: FunctionParameterListSyntax,
        genericParamNames: Set<String> = []
    ) -> String {
        parameters
            .map { parameterStorageType(for: $0, genericParamNames: genericParamNames).description }
            .joined(separator: ", ")
    }

    /// Builds the parameter clause for a separate-parameters handler closure type,
    /// e.g. `"(Int, Int)"`. Callers should only use this when `parameters.count >= 2`.
    static func buildSeparateParameterClause(
        parameters: FunctionParameterListSyntax,
        genericParamNames: Set<String> = []
    ) -> String {
        "(\(buildSeparateParameterTypeList(parameters: parameters, genericParamNames: genericParamNames)))"
    }

    /// The type a parameter is stored and forwarded as: an `@autoclosure`'s evaluated
    /// result type, a variadic's array type, and otherwise the parameter type with
    /// `inout` stripped and generic parameters erased.
    private static func parameterStorageType(
        for param: FunctionParameterSyntax,
        genericParamNames: Set<String>
    ) -> TypeSyntax {
        // An @autoclosure argument is evaluated once when the mock is called, so
        // storage and handlers observe the evaluated value, not the closure itself.
        // (The closure could not be stored anyway: it is non-escaping by default and
        // `@autoclosure` is invalid in stored-type positions.)
        if let resultType = autoclosureResultType(of: param) {
            return eraseGenericTypes(in: resultType, genericParamNames: genericParamNames)
        }
        // Erasure drops every parameter specifier (`inout`, `consuming`, `sending`, ...),
        // which a stored property or closure type cannot carry.
        let erasedType = eraseGenericTypes(in: param.type, genericParamNames: genericParamNames)
        guard param.ellipsis != nil else {
            return erasedType
        }

        return TypeSyntax(ArrayTypeSyntax(element: erasedType))
    }

    /// Returns the function type of an `@autoclosure` parameter
    /// (e.g. `() -> Int` for `@autoclosure () -> Int`), or `nil` when the
    /// parameter is not an autoclosure.
    static func autoclosureFunctionType(of param: FunctionParameterSyntax) -> FunctionTypeSyntax? {
        guard let attributedType = param.type.as(AttributedTypeSyntax.self) else {
            return nil
        }
        let isAutoclosure = attributedType.attributes.contains { element in
            if case .attribute(let attr) = element {
                return attr.attributeName.trimmedDescription == "autoclosure"
            }
            return false
        }
        guard isAutoclosure else {
            return nil
        }
        return attributedType.baseType.as(FunctionTypeSyntax.self)
    }

    /// Returns the result type of an `@autoclosure` parameter
    /// (e.g. `Int` for `@autoclosure () -> Int`), or `nil` when the parameter
    /// is not an autoclosure.
    static func autoclosureResultType(of param: FunctionParameterSyntax) -> TypeSyntax? {
        autoclosureFunctionType(of: param)?.returnClause.type
    }

    /// The statements a witness runs before it touches its arguments: evaluating
    /// `@autoclosure` parameters and rebinding ownership-specified ones. Both shadow the
    /// parameter with a local the rest of the body can use as often as it needs.
    static func buildParameterBindingStatements(
        parameters: FunctionParameterListSyntax
    ) -> [CodeBlockItemSyntax] {
        buildAutoclosureEvaluationStatements(parameters: parameters)
            + buildOwnershipRebindingStatements(parameters: parameters)
    }

    /// Builds one `let <name> = [try ][await ]<name>()` statement per `@autoclosure`
    /// parameter, shadowing the parameter with its evaluated value so call recording
    /// and the handler observe the same value, evaluated exactly once per call.
    /// The `try`/`await` prefix mirrors the autoclosure's own effect specifiers.
    static func buildAutoclosureEvaluationStatements(
        parameters: FunctionParameterListSyntax
    ) -> [CodeBlockItemSyntax] {
        parameters.compactMap { param in
            guard let functionType = autoclosureFunctionType(of: param) else {
                return nil
            }
            let name = (param.secondName ?? param.firstName).text
            let isAsync = functionType.effectSpecifiers?.asyncSpecifier != nil
            let isThrows = functionType.effectSpecifiers?.hasThrowsEffect ?? false
            let prefix = "\(isThrows ? "try " : "")\(isAsync ? "await " : "")"
            return CodeBlockItemSyntax(item: .decl(DeclSyntax(stringLiteral: "let \(name) = \(prefix)\(name)()")))
        }
    }

    /// Builds one rebinding statement per parameter carrying an ownership specifier,
    /// shadowing it with an ordinary local.
    ///
    /// The generated body uses each argument twice — once to record it and once to
    /// forward it to the handler — which an ownership-specified parameter does not
    /// allow: a `consuming` one may be consumed once, and a `borrowing` one not at all.
    /// Rebinding does that once up front, leaving a local the rest of the body can use
    /// freely. A borrowed value has to be copied explicitly, since recording it takes
    /// ownership.
    static func buildOwnershipRebindingStatements(
        parameters: FunctionParameterListSyntax
    ) -> [CodeBlockItemSyntax] {
        parameters.compactMap { param in
            let specifiers = Set(MockGenerator.specifiers(of: param.type))
            guard !specifiers.isDisjoint(with: ownershipSpecifiers) else {
                return nil
            }
            let name = (param.secondName ?? param.firstName).text
            let value = specifiers.isDisjoint(with: borrowedSpecifiers) ? name : "copy \(name)"
            return CodeBlockItemSyntax(item: .decl(DeclSyntax(stringLiteral: "let \(name) = \(value)")))
        }
    }

    /// The specifiers that constrain how often an argument may be used. `inout` is not
    /// among them: it names a mutable binding the witness writes back to, not a
    /// transfer of ownership, and rebinding it would break the write-back.
    private static let ownershipSpecifiers: Set<String> = ["consuming", "borrowing", "__owned", "__shared"]

    /// The specifiers that lend a value rather than transfer it, so the rebinding has
    /// to copy instead of taking what it was given.
    private static let borrowedSpecifiers: Set<String> = ["borrowing", "__shared"]

    /// Whether any `@autoclosure` parameter can throw, and so is evaluated with `try` in the
    /// requirement's own body rather than inside the handler call.
    static func hasThrowingAutoclosureParameter(_ parameters: FunctionParameterListSyntax) -> Bool {
        parameters.contains { param in
            guard let functionType = autoclosureFunctionType(of: param) else {
                return false
            }
            return functionType.effectSpecifiers?.hasThrowsEffect ?? false
        }
    }

    /// The recorded-arguments value, shaped to match `buildParameterTupleType`:
    /// `()` for no parameters, the bare name for one, and a labeled tuple for several.
    static func buildArgsExpression(parameters: FunctionParameterListSyntax) -> ExprSyntax {
        if parameters.isEmpty {
            return ExprSyntax(TupleExprSyntax(elements: LabeledExprListSyntax([])))
        }

        if parameters.count == 1, let param = parameters.first {
            let paramName = (param.secondName ?? param.firstName).text
            return ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier(paramName)))
        }

        let tupleElements = parameters.enumerated().map { index, param -> LabeledExprSyntax in
            let paramName = (param.secondName ?? param.firstName).text
            let isLast = index == parameters.count - 1
            return LabeledExprSyntax(
                label: MockGenerator.recordedArgumentLabel(of: param),
                colon: .colonToken(trailingTrivia: .space),
                expression: DeclReferenceExprSyntax(baseName: .identifier(paramName)),
                trailingComma: isLast ? nil : .commaToken(trailingTrivia: .space)
            )
        }

        return ExprSyntax(TupleExprSyntax(elements: LabeledExprListSyntax(tupleElements)))
    }
}
