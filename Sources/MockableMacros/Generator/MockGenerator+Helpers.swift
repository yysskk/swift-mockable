import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Conditional Compilation Support

/// Represents a protocol member that may be wrapped in conditional compilation (e.g., #if DEBUG)
struct ConditionalMember {
    let decl: DeclSyntax
    let condition: ExprSyntax?  // nil means unconditional

    var isConditional: Bool {
        condition != nil
    }
}

// MARK: - Helper Methods

extension MockGenerator {
    /// Extracts all members from the protocol, including those inside #if blocks.
    /// Returns an array of ConditionalMember, where each member knows its condition (if any).
    func extractConditionalMembers() -> [ConditionalMember] {
        var result: [ConditionalMember] = []

        for member in members {
            if let ifConfigDecl = member.decl.as(IfConfigDeclSyntax.self) {
                // Handle #if blocks
                for clause in ifConfigDecl.clauses {
                    // Skip clauses without a condition (e.g., #else), since they are still conditional
                    guard let condition = clause.condition,
                          let elements = clause.elements else { continue }

                    if case .decls(let declList) = elements {
                        for declItem in declList {
                            result.append(ConditionalMember(decl: declItem.decl, condition: condition))
                        }
                    }
                }
            } else {
                // Regular unconditional member
                result.append(ConditionalMember(decl: member.decl, condition: nil))
            }
        }

        return result
    }

    /// Groups function declarations by their name, including conditional members.
    /// This is used to detect overloaded methods.
    func groupMethodsByNameIncludingConditional() -> [String: [FunctionDeclSyntax]] {
        var methodGroups: [String: [FunctionDeclSyntax]] = [:]

        for conditionalMember in extractConditionalMembers() {
            if let funcDecl = conditionalMember.decl.as(FunctionDeclSyntax.self) {
                let funcName = funcDecl.name.text
                methodGroups[funcName, default: []].append(funcDecl)
            }
        }

        return methodGroups
    }

    /// Wraps a list of MemberBlockItemSyntax in an IfConfigDecl with the given condition.
    static func wrapInIfConfig(members: [MemberBlockItemSyntax], condition: ExprSyntax) -> MemberBlockItemSyntax {
        let ifConfigDecl = IfConfigDeclSyntax(
            clauses: IfConfigClauseListSyntax([
                IfConfigClauseSyntax(
                    poundKeyword: .poundIfToken(),
                    condition: condition,
                    elements: .decls(MemberBlockItemListSyntax(members))
                )
            ])
        )
        return MemberBlockItemSyntax(decl: ifConfigDecl)
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
            return eraseGenericTypes(in: param.type, genericParamNames: genericParamNames)
        }

        let tupleElements = parameters.enumerated().map { index, param -> TupleTypeElementSyntax in
            let isLast = index == parameters.count - 1
            let erasedType = eraseGenericTypes(in: param.type, genericParamNames: genericParamNames)
            return TupleTypeElementSyntax(
                firstName: param.secondName ?? param.firstName,
                colon: .colonToken(trailingTrivia: .space),
                type: erasedType,
                trailingComma: isLast ? nil : .commaToken(trailingTrivia: .space)
            )
        }

        return TypeSyntax(TupleTypeSyntax(elements: TupleTypeElementListSyntax(tupleElements)))
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
