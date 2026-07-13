import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Conditional Compilation Support

extension MockGenerator {
    func collectDeclsIncludingConditional(from members: MemberBlockItemListSyntax? = nil) -> [DeclSyntax] {
        collectDecls(from: members ?? self.members)
    }

    /// Groups function declarations by their name, including conditional members.
    /// This is used to detect overloaded methods.
    func groupMethodsByNameIncludingConditional() -> [String: [FunctionDeclSyntax]] {
        var methodGroups: [String: [FunctionDeclSyntax]] = [:]

        for decl in collectDeclsIncludingConditional() {
            if let funcDecl = decl.as(FunctionDeclSyntax.self) {
                let funcName = funcDecl.name.text
                methodGroups[funcName, default: []].append(funcDecl)
            }
        }

        return methodGroups
    }

    func hasTypeMembers() -> Bool {
        collectDeclsIncludingConditional().contains { Self.isTypeMember($0) }
    }

    static func isTypeMember(_ decl: DeclSyntax) -> Bool {
        if let funcDecl = decl.as(FunctionDeclSyntax.self) {
            return isTypeMember(funcDecl.modifiers)
        }

        if let varDecl = decl.as(VariableDeclSyntax.self) {
            return isTypeMember(varDecl.modifiers)
        }

        if let subscriptDecl = decl.as(SubscriptDeclSyntax.self) {
            return isTypeMember(subscriptDecl.modifiers)
        }

        return false
    }

    static func isTypeMember(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { modifier in
            let modifierName = modifier.name.text
            return modifierName == "static" || modifierName == "class"
        }
    }

    static func typeMemberModifiers(isTypeMember: Bool) -> [DeclModifierSyntax] {
        guard isTypeMember else {
            return []
        }

        return [DeclModifierSyntax(name: .keyword(.static))]
    }

    static func storagePropertyName(isTypeMember: Bool) -> String {
        MockNaming.storageName(isTypeMember: isTypeMember)
    }

    var usesInstanceStorageLock: Bool {
        isActor || isSendable
    }

    func usesLockBasedStorage(isTypeMember: Bool) -> Bool {
        usesInstanceStorageLock || isTypeMember
    }

    func generateAssociatedTypeMembers() -> [MemberBlockItemSyntax] {
        mapMemberBlockItemsPreservingIfConfig { decl in
            if let associatedType = decl.as(AssociatedTypeDeclSyntax.self) {
                return [MemberBlockItemSyntax(decl: generateTypeAlias(for: associatedType))]
            }

            if let typeAliasDecl = decl.as(TypeAliasDeclSyntax.self) {
                let rebuilt = TypeAliasDeclSyntax(
                    modifiers: buildModifiers(),
                    name: .identifier(typeAliasDecl.name.text),
                    initializer: TypeInitializerClauseSyntax(
                        equal: .equalToken(leadingTrivia: .space, trailingTrivia: .space),
                        value: typeAliasDecl.initializer.value
                    )
                )
                return [MemberBlockItemSyntax(decl: rebuilt)]
            }

            return []
        }
    }

    func mapMemberBlockItemsPreservingIfConfig(
        from members: MemberBlockItemListSyntax? = nil,
        transform: (DeclSyntax) -> [MemberBlockItemSyntax]
    ) -> [MemberBlockItemSyntax] {
        var result: [MemberBlockItemSyntax] = []

        for member in members ?? self.members {
            if let ifConfigDecl = member.decl.as(IfConfigDeclSyntax.self) {
                guard let mappedIfConfig = mapIfConfigDeclToMembers(ifConfigDecl, transform: transform) else {
                    continue
                }
                result.append(MemberBlockItemSyntax(decl: DeclSyntax(mappedIfConfig)))
            } else {
                result.append(contentsOf: transform(member.decl))
            }
        }

        return result
    }

    func mapCodeBlockItemsPreservingIfConfig(
        from members: MemberBlockItemListSyntax? = nil,
        transform: (DeclSyntax) -> [CodeBlockItemSyntax]
    ) -> [CodeBlockItemSyntax] {
        var result: [CodeBlockItemSyntax] = []

        for member in members ?? self.members {
            if let ifConfigDecl = member.decl.as(IfConfigDeclSyntax.self) {
                guard let mappedIfConfig = mapIfConfigDeclToStatements(ifConfigDecl, transform: transform) else {
                    continue
                }
                result.append(CodeBlockItemSyntax(item: .decl(DeclSyntax(mappedIfConfig))))
            } else {
                result.append(contentsOf: transform(member.decl))
            }
        }

        return result
    }

    func mapLinesPreservingIfConfig(
        from members: MemberBlockItemListSyntax? = nil,
        transform: (DeclSyntax) -> [String]
    ) -> [String] {
        var result: [String] = []

        for member in members ?? self.members {
            if let ifConfigDecl = member.decl.as(IfConfigDeclSyntax.self) {
                result.append(contentsOf: mapIfConfigDeclToLines(ifConfigDecl, transform: transform))
            } else {
                result.append(contentsOf: transform(member.decl))
            }
        }

        return result
    }

    private func collectDecls(from members: MemberBlockItemListSyntax) -> [DeclSyntax] {
        var result: [DeclSyntax] = []

        for member in members {
            if let ifConfigDecl = member.decl.as(IfConfigDeclSyntax.self) {
                result.append(contentsOf: collectDecls(from: ifConfigDecl))
            } else {
                result.append(member.decl)
            }
        }

        return result
    }

    private func collectDecls(from ifConfigDecl: IfConfigDeclSyntax) -> [DeclSyntax] {
        var result: [DeclSyntax] = []

        for clause in ifConfigDecl.clauses {
            guard clause.condition != nil,
                  let elements = clause.elements,
                  case .decls(let decls) = elements else {
                continue
            }

            result.append(contentsOf: collectDecls(from: decls))
        }

        return result
    }

    private func mapIfConfigDeclToMembers(
        _ ifConfigDecl: IfConfigDeclSyntax,
        transform: (DeclSyntax) -> [MemberBlockItemSyntax]
    ) -> IfConfigDeclSyntax? {
        var hasGeneratedContent = false

        let clauses = IfConfigClauseListSyntax(
            ifConfigDecl.clauses.map { clause in
                let mappedElements: IfConfigClauseSyntax.Elements?
                if let elements = clause.elements,
                   case .decls(let decls) = elements {
                    let mappedMembers = mapMemberBlockItemsPreservingIfConfig(from: decls, transform: transform)
                    if !mappedMembers.isEmpty {
                        hasGeneratedContent = true
                    }
                    mappedElements = .decls(MemberBlockItemListSyntax(mappedMembers))
                } else {
                    mappedElements = clause.elements
                }

                return IfConfigClauseSyntax(
                    poundKeyword: normalizedPoundKeyword(for: clause),
                    condition: clause.condition,
                    elements: mappedElements
                )
            }
        )

        guard hasGeneratedContent else {
            return nil
        }

        return IfConfigDeclSyntax(clauses: clauses)
    }

    private func mapIfConfigDeclToStatements(
        _ ifConfigDecl: IfConfigDeclSyntax,
        transform: (DeclSyntax) -> [CodeBlockItemSyntax]
    ) -> IfConfigDeclSyntax? {
        var hasGeneratedContent = false

        let clauses = IfConfigClauseListSyntax(
            ifConfigDecl.clauses.map { clause in
                let mappedElements: IfConfigClauseSyntax.Elements?
                if let elements = clause.elements,
                   case .decls(let decls) = elements {
                    let mappedStatements = mapCodeBlockItemsPreservingIfConfig(from: decls, transform: transform)
                    if !mappedStatements.isEmpty {
                        hasGeneratedContent = true
                    }
                    mappedElements = .statements(CodeBlockItemListSyntax(mappedStatements))
                } else {
                    mappedElements = clause.elements
                }

                return IfConfigClauseSyntax(
                    poundKeyword: normalizedPoundKeyword(for: clause),
                    condition: clause.condition,
                    elements: mappedElements
                )
            }
        )

        guard hasGeneratedContent else {
            return nil
        }

        return IfConfigDeclSyntax(clauses: clauses)
    }

    private func mapIfConfigDeclToLines(
        _ ifConfigDecl: IfConfigDeclSyntax,
        transform: (DeclSyntax) -> [String]
    ) -> [String] {
        var lines: [String] = []
        var hasGeneratedContent = false

        for clause in ifConfigDecl.clauses {
            let mappedLines: [String]
            if let elements = clause.elements,
               case .decls(let decls) = elements {
                mappedLines = mapLinesPreservingIfConfig(from: decls, transform: transform)
            } else {
                mappedLines = []
            }

            if !mappedLines.isEmpty {
                hasGeneratedContent = true
            }

            if let condition = clause.condition {
                lines.append("\(clause.poundKeyword.text) \(condition.trimmedDescription)")
            } else {
                lines.append(clause.poundKeyword.text)
            }
            lines.append(contentsOf: mappedLines)
        }

        guard hasGeneratedContent else {
            return []
        }

        lines.append("#endif")
        return lines
    }

    private func normalizedPoundKeyword(for clause: IfConfigClauseSyntax) -> TokenSyntax {
        switch clause.poundKeyword.text {
        case "#if":
            return .poundIfToken()
        case "#elseif":
            return .poundElseifToken()
        case "#else":
            return .poundElseToken()
        default:
            return clause.poundKeyword.with(\.leadingTrivia, []).with(\.trailingTrivia, [])
        }
    }

    static func extractGenericParameterNames(from funcDecl: FunctionDeclSyntax) -> Set<String> {
        guard let genericClause = funcDecl.genericParameterClause else {
            return []
        }
        return Set(genericClause.parameters.map { $0.name.text })
    }

    static func extractGenericParameterNames(from initDecl: InitializerDeclSyntax) -> Set<String> {
        guard let genericClause = initDecl.genericParameterClause else {
            return []
        }
        return Set(genericClause.parameters.map { $0.name.text })
    }

    /// All initializer requirements declared by the protocol, including those nested in
    /// conditional-compilation blocks. Used to detect `init` overloads and to decide
    /// whether the mock declares its own initializers.
    func collectInitializers() -> [InitializerDeclSyntax] {
        collectDeclsIncludingConditional().compactMap { $0.as(InitializerDeclSyntax.self) }
    }

    /// Whether the protocol declares at least one `init` requirement.
    var hasInitializerRequirements: Bool {
        collectDeclsIncludingConditional().contains { $0.is(InitializerDeclSyntax.self) }
    }

    /// The tracking identifier for an initializer within its overload group, e.g. `init`
    /// for a sole initializer or `initString` for an overload taking a `String`.
    static func initializerIdentifier(for initDecl: InitializerDeclSyntax, in group: [InitializerDeclSyntax]) -> String {
        let suffix = group.count > 1 ? initializerIdentifierSuffix(from: initDecl, in: group) : ""
        return MockNaming.initializerIdentifier(suffix: suffix)
    }

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
                firstName: param.secondName ?? param.firstName,
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
        let normalizedType = stripInOutKeyword(from: param.type)
        let erasedType = eraseGenericTypes(in: normalizedType, genericParamNames: genericParamNames)
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

    private static func stripInOutKeyword(from type: TypeSyntax) -> TypeSyntax {
        let trimmed = type.trimmedDescription
        guard trimmed.hasPrefix("inout ") else {
            return type
        }
        return TypeSyntax(stringLiteral: String(trimmed.dropFirst("inout ".count)))
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

        if let identifierType = type.as(IdentifierTypeSyntax.self),
           let erased = eraseIdentifierType(identifierType, genericParamNames: genericParamNames) {
            return erased
        }
        if let optionalType = type.as(OptionalTypeSyntax.self),
           let erased = eraseOptionalType(optionalType, genericParamNames: genericParamNames) {
            return erased
        }
        if let arrayType = type.as(ArrayTypeSyntax.self),
           let erased = eraseArrayType(arrayType, genericParamNames: genericParamNames) {
            return erased
        }

        return type
    }

    /// Strips `@escaping` (invalid outside parameter position) and recurses into the
    /// base type, e.g. `@escaping @Sendable (Event) -> Void`. Runs regardless of
    /// `genericParamNames` so `@escaping` is removed even for non-generic closures.
    private static func eraseAttributedType(
        _ attributedType: AttributedTypeSyntax,
        genericParamNames: Set<String>
    ) -> TypeSyntax {
        let filteredAttributes = stripEscapingAttribute(from: attributedType.attributes)
        let processedBaseType = eraseGenericTypes(in: attributedType.baseType, genericParamNames: genericParamNames)

        if filteredAttributes.isEmpty && !attributedType.hasSpecifiers {
            return processedBaseType
        }

        return TypeSyntax(AttributedTypeSyntax.makeAttributedType(
            from: attributedType,
            attributes: filteredAttributes,
            baseType: processedBaseType
        ))
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
        return TypeSyntax(OptionalTypeSyntax(wrappedType: erasedWrapped))
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

    /// Replaces a bare generic parameter (`T`) or a generic type that mentions one
    /// (e.g. `UserDefaultsKey<T>`) with `Any`. Returns `nil` for identifiers that
    /// reference no generic parameter, so the caller leaves them unchanged.
    private static func eraseIdentifierType(
        _ identifierType: IdentifierTypeSyntax,
        genericParamNames: Set<String>
    ) -> TypeSyntax? {
        if genericParamNames.contains(identifierType.name.text) {
            return TypeSyntax(stringLiteral: "Any")
        }
        if let genericArgs = identifierType.genericArgumentClause {
            let hasGenericParam = genericArgumentsContainType(genericArgs.arguments) { typeSyntax in
                if let innerIdent = typeSyntax.as(IdentifierTypeSyntax.self) {
                    return genericParamNames.contains(innerIdent.name.text)
                }
                return false
            }
            if hasGenericParam {
                return TypeSyntax(stringLiteral: "Any")
            }
        }
        return nil
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
        return TypeSyntax(OptionalTypeSyntax(wrappedType: erasedWrapped))
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

    static func typeContainsGeneric(_ type: TypeSyntax, genericParamNames: Set<String>) -> Bool {
        if genericParamNames.isEmpty {
            return false
        }

        if let identifierType = type.as(IdentifierTypeSyntax.self) {
            if genericParamNames.contains(identifierType.name.text) {
                return true
            }
            if let genericArgs = identifierType.genericArgumentClause {
                return genericArgumentsContainType(genericArgs.arguments) { typeSyntax in
                    typeContainsGeneric(typeSyntax, genericParamNames: genericParamNames)
                }
            }
        }

        if let optionalType = type.as(OptionalTypeSyntax.self) {
            return typeContainsGeneric(optionalType.wrappedType, genericParamNames: genericParamNames)
        }

        if let arrayType = type.as(ArrayTypeSyntax.self) {
            return typeContainsGeneric(arrayType.element, genericParamNames: genericParamNames)
        }

        return false
    }

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
    private static func unwrapForDefaultDetection(_ type: TypeSyntax) -> TypeSyntax {
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

    private static func isOptionalType(_ type: TypeSyntax) -> Bool {
        if type.is(OptionalTypeSyntax.self) || type.is(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return true
        }
        return isGenericStdlibType(type, named: "Optional")
    }

    private static func isArrayType(_ type: TypeSyntax) -> Bool {
        if type.is(ArrayTypeSyntax.self) {
            return true
        }
        return isGenericStdlibType(type, named: "Array")
    }

    private static func isSetType(_ type: TypeSyntax) -> Bool {
        isGenericStdlibType(type, named: "Set")
    }

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
                label: param.secondName ?? param.firstName,
                colon: .colonToken(trailingTrivia: .space),
                expression: DeclReferenceExprSyntax(baseName: .identifier(paramName)),
                trailingComma: isLast ? nil : .commaToken(trailingTrivia: .space)
            )
        }

        return ExprSyntax(TupleExprSyntax(elements: LabeledExprListSyntax(tupleElements)))
    }

    // MARK: - Function Identifier Suffix

    /// Generates a unique suffix based on parameter types to distinguish overloaded functions.
    /// Example: `func set(_ value: Bool, forKey: Key)` -> "BoolKey"
    static func functionIdentifierSuffix(from funcDecl: FunctionDeclSyntax) -> String {
        let parameters = funcDecl.signature.parameterClause.parameters
        if parameters.isEmpty {
            return ""
        }

        let typeNames = parameters.map { param -> String in
            let typeName = param.type.trimmedDescription
            return sanitizeTypeName(typeName)
        }

        return typeNames.joined()
    }

    /// Generates a unique suffix for an overloaded function within a group of methods with the same name.
    /// First attempts to use parameter types only. If that results in duplicates within the group,
    /// adds return type and async/throws modifiers to disambiguate. If overloads still collide
    /// (e.g. nested generics that sanitize identically, such as `Foo<Bar, Baz>` and `Foo<BarBaz>`),
    /// a deterministic source-order ordinal is appended so generated names stay unique.
    static func functionIdentifierSuffix(from funcDecl: FunctionDeclSyntax, in methodGroup: [FunctionDeclSyntax]) -> String {
        let baseSuffix = functionIdentifierSuffix(from: funcDecl)

        // Check if there are duplicates with the same base suffix in the method group
        let baseCollisions = methodGroup.filter { functionIdentifierSuffix(from: $0) == baseSuffix }

        if baseCollisions.count <= 1 {
            // No duplicates, use base suffix
            return baseSuffix
        }

        // There are duplicates, add return type and async/throws to disambiguate
        let extendedSuffix = extendedFunctionIdentifierSuffix(from: funcDecl, baseSuffix: baseSuffix)

        let extendedCollisions = baseCollisions.filter {
            extendedFunctionIdentifierSuffix(from: $0, baseSuffix: functionIdentifierSuffix(from: $0)) == extendedSuffix
        }
        guard extendedCollisions.count > 1 else {
            return extendedSuffix
        }

        // Still colliding: append a deterministic 1-based ordinal by source order.
        // The first colliding overload keeps the extended suffix for stability.
        guard let index = extendedCollisions.firstIndex(where: { $0.id == funcDecl.id }), index > 0 else {
            return extendedSuffix
        }
        return "\(extendedSuffix)\(index + 1)"
    }

    /// Generates an extended suffix that includes return type and async/throws modifiers.
    private static func extendedFunctionIdentifierSuffix(from funcDecl: FunctionDeclSyntax, baseSuffix: String) -> String {
        var suffix = baseSuffix

        // Add return type if present and not Void
        if let returnClause = funcDecl.signature.returnClause {
            let returnTypeName = returnClause.type.trimmedDescription
            if returnTypeName != "Void" && returnTypeName != "()" {
                suffix += sanitizeTypeName(returnTypeName)
            }
        }

        // Add async modifier
        if funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil {
            suffix += "Async"
        }

        // Add throws modifier
        if funcDecl.signature.effectSpecifiers?.hasThrowsEffect == true {
            suffix += "Throwing"
        }

        return suffix
    }

    // MARK: - Initializer Identifier Suffix

    /// Generates a suffix based on parameter types to distinguish overloaded initializers,
    /// mirroring `functionIdentifierSuffix(from:)`. Example: `init(host: String, port: Int)`
    /// -> "StringInt".
    static func initializerIdentifierSuffix(from initDecl: InitializerDeclSyntax) -> String {
        let parameters = initDecl.signature.parameterClause.parameters
        if parameters.isEmpty {
            return ""
        }

        return parameters
            .map { sanitizeTypeName($0.type.trimmedDescription) }
            .joined()
    }

    /// Generates a unique suffix for an overloaded initializer within a group of `init`
    /// requirements. Mirrors the function overload logic: parameter types first, then
    /// `async`/`throws` modifiers, then a deterministic source-order ordinal if overloads
    /// still collide. Initializers have no return type, so that disambiguator does not apply.
    static func initializerIdentifierSuffix(from initDecl: InitializerDeclSyntax, in group: [InitializerDeclSyntax]) -> String {
        let baseSuffix = initializerIdentifierSuffix(from: initDecl)

        let baseCollisions = group.filter { initializerIdentifierSuffix(from: $0) == baseSuffix }
        if baseCollisions.count <= 1 {
            return baseSuffix
        }

        let extendedSuffix = extendedInitializerIdentifierSuffix(from: initDecl, baseSuffix: baseSuffix)
        let extendedCollisions = baseCollisions.filter {
            extendedInitializerIdentifierSuffix(from: $0, baseSuffix: initializerIdentifierSuffix(from: $0)) == extendedSuffix
        }
        guard extendedCollisions.count > 1 else {
            return extendedSuffix
        }

        // Still colliding: append a deterministic 1-based ordinal by source order. The first
        // colliding overload keeps the extended suffix for stability.
        guard let index = extendedCollisions.firstIndex(where: { $0.id == initDecl.id }), index > 0 else {
            return extendedSuffix
        }
        return "\(extendedSuffix)\(index + 1)"
    }

    /// Extends an initializer suffix with `async`/`throws` modifiers to disambiguate overloads
    /// whose parameter types sanitize identically.
    private static func extendedInitializerIdentifierSuffix(from initDecl: InitializerDeclSyntax, baseSuffix: String) -> String {
        var suffix = baseSuffix

        if initDecl.signature.effectSpecifiers?.asyncSpecifier != nil {
            suffix += "Async"
        }

        if initDecl.signature.effectSpecifiers?.hasThrowsEffect == true {
            suffix += "Throwing"
        }

        return suffix
    }

    /// Sanitizes a type name for use in an identifier.
    /// Handles special characters, generics, optionals, and arrays.
    static func sanitizeTypeName(_ typeName: String) -> String {
        var result = typeName

        // Handle optional types
        if result.hasSuffix("?") {
            result = sanitizeTypeName(String(result.dropLast())) + "Optional"
            return result
        }

        // Handle implicitly unwrapped optionals
        if result.hasSuffix("!") {
            result = sanitizeTypeName(String(result.dropLast())) + "ImplicitlyUnwrapped"
            return result
        }

        // Handle array types [T]
        if result.hasPrefix("[") && result.hasSuffix("]") {
            let inner = String(result.dropFirst().dropLast())
            result = sanitizeTypeName(inner) + "Array"
            return result
        }

        // Handle generic types like Dictionary<K, V> or Array<T>
        if let openAngleIndex = result.firstIndex(of: "<"),
           let closeAngleIndex = result.lastIndex(of: ">") {
            let baseName = String(result[..<openAngleIndex])
            let genericArgsStr = String(result[result.index(after: openAngleIndex)..<closeAngleIndex])
            // Split generic arguments by comma, handling nested generics
            let genericArgs = splitGenericArguments(genericArgsStr)
            let sanitizedArgs = genericArgs.map { sanitizeTypeName($0.trimmingCharacters(in: .whitespaces)) }
            result = baseName + sanitizedArgs.joined()
        }

        // Remove any remaining special characters
        result = result.filter { $0.isLetter || $0.isNumber }

        // Ensure first letter is uppercase
        if let first = result.first {
            result = first.uppercased() + result.dropFirst()
        }

        return result
    }

    /// Splits generic arguments by comma, handling nested generics.
    /// E.g., "String, Dictionary<Int, String>" -> ["String", "Dictionary<Int, String>"]
    private static func splitGenericArguments(_ args: String) -> [String] {
        var result: [String] = []
        var current = ""
        var depth = 0

        for char in args {
            if char == "<" {
                depth += 1
                current.append(char)
            } else if char == ">" {
                depth -= 1
                current.append(char)
            } else if char == "," && depth == 0 {
                result.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }

        if !current.isEmpty {
            result.append(current)
        }

        return result
    }
}
