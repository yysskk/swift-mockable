import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Helper Methods

extension MockGenerator {
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
}
