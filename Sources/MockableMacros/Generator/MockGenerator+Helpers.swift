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

    func generateAssociatedTypeMembers() -> [MemberBlockItemSyntax] {
        mapMemberBlockItemsPreservingIfConfig { decl in
            guard let associatedType = decl.as(AssociatedTypeDeclSyntax.self) else {
                return []
            }

            return [MemberBlockItemSyntax(decl: generateTypeAlias(for: associatedType))]
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
            guard let elements = clause.elements,
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

    private static func parameterStorageType(
        for param: FunctionParameterSyntax,
        genericParamNames: Set<String>
    ) -> TypeSyntax {
        let normalizedType = stripInOutKeyword(from: param.type)
        let erasedType = eraseGenericTypes(in: normalizedType, genericParamNames: genericParamNames)
        guard param.ellipsis != nil else {
            return erasedType
        }

        return TypeSyntax(ArrayTypeSyntax(element: erasedType))
    }

    private static func stripInOutKeyword(from type: TypeSyntax) -> TypeSyntax {
        let trimmed = type.trimmedDescription
        guard trimmed.hasPrefix("inout ") else {
            return type
        }
        return TypeSyntax(stringLiteral: String(trimmed.dropFirst("inout ".count)))
    }

    static func eraseGenericTypes(in type: TypeSyntax, genericParamNames: Set<String>) -> TypeSyntax {
        // Handle attributed types FIRST (e.g., @escaping @Sendable (Event) -> Void)
        // This must be checked before the genericParamNames.isEmpty early return
        // because we need to strip @escaping even when there are no generic parameters
        if let attributedType = type.as(AttributedTypeSyntax.self) {
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

        if genericParamNames.isEmpty {
            return type
        }

        // Check if type itself is a generic parameter
        if let identifierType = type.as(IdentifierTypeSyntax.self) {
            if genericParamNames.contains(identifierType.name.text) {
                return TypeSyntax(stringLiteral: "Any")
            }
            // Check for generic arguments like UserDefaultsKey<T>
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
        }

        // Handle optional types
        if let optionalType = type.as(OptionalTypeSyntax.self) {
            let erasedWrapped = eraseGenericTypes(in: optionalType.wrappedType, genericParamNames: genericParamNames)
            if erasedWrapped.description != optionalType.wrappedType.description {
                return TypeSyntax(OptionalTypeSyntax(wrappedType: erasedWrapped))
            }
        }

        // Handle implicitly unwrapped optional types
        if let implicitOptional = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            let erasedWrapped = eraseGenericTypes(in: implicitOptional.wrappedType, genericParamNames: genericParamNames)
            if erasedWrapped.description != implicitOptional.wrappedType.description {
                return TypeSyntax(ImplicitlyUnwrappedOptionalTypeSyntax(wrappedType: erasedWrapped))
            }
        }

        // Handle array types
        if let arrayType = type.as(ArrayTypeSyntax.self) {
            let erasedElement = eraseGenericTypes(in: arrayType.element, genericParamNames: genericParamNames)
            if erasedElement.description != arrayType.element.description {
                return TypeSyntax(ArrayTypeSyntax(element: erasedElement))
            }
        }

        // Handle function types (closures) - recursively process parameter types and return type
        if let funcType = type.as(FunctionTypeSyntax.self) {
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
                effectSpecifiers: funcType.effectSpecifiers,
                returnClause: ReturnClauseSyntax(
                    arrow: funcType.returnClause.arrow,
                    type: processedReturnType
                )
            ))
        }

        return type
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
    /// adds return type and async/throws modifiers to disambiguate.
    static func functionIdentifierSuffix(from funcDecl: FunctionDeclSyntax, in methodGroup: [FunctionDeclSyntax]) -> String {
        let baseSuffix = functionIdentifierSuffix(from: funcDecl)

        // Check if there are duplicates with the same base suffix in the method group
        let duplicateCount = methodGroup.filter { functionIdentifierSuffix(from: $0) == baseSuffix }.count

        if duplicateCount <= 1 {
            // No duplicates, use base suffix
            return baseSuffix
        }

        // There are duplicates, need to add more distinguishing information
        return extendedFunctionIdentifierSuffix(from: funcDecl, baseSuffix: baseSuffix)
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
