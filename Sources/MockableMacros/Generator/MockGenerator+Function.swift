import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Function Mock Generation

extension MockGenerator {
    func generateFunctionMock(_ funcDecl: FunctionDeclSyntax, suffix: String = "") -> [MemberBlockItemSyntax] {
        var members: [MemberBlockItemSyntax] = []

        let funcName = funcDecl.name.text
        let identifier = suffix.isEmpty ? funcName : "\(funcName)\(suffix)"
        let parameters = funcDecl.signature.parameterClause.parameters
        let returnType = funcDecl.signature.returnClause?.type
        let isAsync = funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil
        let isThrows = funcDecl.signature.effectSpecifiers?.hasThrowsEffect ?? false
        let genericParamNames = Self.extractGenericParameterNames(from: funcDecl)

        if isSendable {
            // For Sendable protocols, generate computed properties that access the Mutex
            let callCountProperty = generateSendableCallCountProperty(identifier: identifier)
            members.append(MemberBlockItemSyntax(decl: callCountProperty))

            let callArgsProperty = generateSendableCallArgsProperty(
                identifier: identifier,
                parameters: parameters,
                genericParamNames: genericParamNames
            )
            members.append(MemberBlockItemSyntax(decl: callArgsProperty))

            let handlerProperty = generateSendableHandlerProperty(
                identifier: identifier,
                parameters: parameters,
                returnType: returnType,
                isAsync: isAsync,
                isThrows: isThrows,
                genericParamNames: genericParamNames
            )
            members.append(MemberBlockItemSyntax(decl: handlerProperty))

            let mockFunction = generateSendableMockFunction(funcDecl, identifier: identifier, genericParamNames: genericParamNames)
            members.append(MemberBlockItemSyntax(decl: mockFunction))
        } else {
            // Generate call count property
            let callCountProperty = generateCallCountProperty(identifier: identifier)
            members.append(MemberBlockItemSyntax(decl: callCountProperty))

            // Generate call arguments storage
            let callArgsProperty = generateCallArgsProperty(
                identifier: identifier,
                parameters: parameters,
                genericParamNames: genericParamNames
            )
            members.append(MemberBlockItemSyntax(decl: callArgsProperty))

            // Generate handler property
            let handlerProperty = generateHandlerProperty(
                identifier: identifier,
                parameters: parameters,
                returnType: returnType,
                isAsync: isAsync,
                isThrows: isThrows,
                genericParamNames: genericParamNames
            )
            members.append(MemberBlockItemSyntax(decl: handlerProperty))

            // Generate the mock function implementation
            let mockFunction = generateMockFunction(funcDecl, identifier: identifier, genericParamNames: genericParamNames)
            members.append(MemberBlockItemSyntax(decl: mockFunction))
        }

        return members
    }

    private func generateCallCountProperty(identifier: String) -> VariableDeclSyntax {
        VariableDeclSyntax(
            modifiers: buildModifiers(),
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier("\(identifier)CallCount")),
                    typeAnnotation: TypeAnnotationSyntax(type: TypeSyntax(stringLiteral: "Int")),
                    initializer: InitializerClauseSyntax(value: IntegerLiteralExprSyntax(literal: .integerLiteral("0")))
                )
            ])
        )
    }

    private func generateCallArgsProperty(
        identifier: String,
        parameters: FunctionParameterListSyntax,
        genericParamNames: Set<String>
    ) -> VariableDeclSyntax {
        let tupleType = Self.buildParameterTupleType(parameters: parameters, genericParamNames: genericParamNames)

        return VariableDeclSyntax(
            modifiers: buildModifiers(),
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier("\(identifier)CallArgs")),
                    typeAnnotation: TypeAnnotationSyntax(
                        type: ArrayTypeSyntax(element: tupleType)
                    ),
                    initializer: InitializerClauseSyntax(
                        value: ArrayExprSyntax(elements: ArrayElementListSyntax([]))
                    )
                )
            ])
        )
    }

    private func generateHandlerProperty(
        identifier: String,
        parameters: FunctionParameterListSyntax,
        returnType: TypeSyntax?,
        isAsync: Bool,
        isThrows: Bool,
        genericParamNames: Set<String>
    ) -> VariableDeclSyntax {
        let paramTupleType = Self.buildParameterTupleType(
            parameters: parameters,
            genericParamNames: genericParamNames
        )
        let erasedReturnType = returnType.map { Self.eraseGenericTypes(in: $0, genericParamNames: genericParamNames) }
        let returnTypeStr = erasedReturnType?.description ?? "Void"

        var closureType = parameters.isEmpty ? "()" : "(\(paramTupleType.description))"
        if isAsync {
            closureType += " async"
        }
        if isThrows {
            closureType += " throws"
        }
        closureType += " -> \(returnTypeStr)"

        return VariableDeclSyntax(
            modifiers: buildModifiers(),
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier("\(identifier)Handler")),
                    typeAnnotation: TypeAnnotationSyntax(
                        type: OptionalTypeSyntax(wrappedType: TypeSyntax(stringLiteral: "(@Sendable \(closureType))"))
                    ),
                    initializer: InitializerClauseSyntax(value: NilLiteralExprSyntax())
                )
            ])
        )
    }

    private func generateMockFunction(_ funcDecl: FunctionDeclSyntax, identifier: String, genericParamNames: Set<String>) -> FunctionDeclSyntax {
        let parameters = funcDecl.signature.parameterClause.parameters
        let returnType = funcDecl.signature.returnClause?.type
        let isAsync = funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil
        let isThrows = funcDecl.signature.effectSpecifiers?.hasThrowsEffect ?? false
        let hasGenericReturn = returnType.map { Self.typeContainsGeneric($0, genericParamNames: genericParamNames) } ?? false

        // Build function body
        var statements: [CodeBlockItemSyntax] = []

        // Increment call count
        let incrementStmt = InfixOperatorExprSyntax(
            leftOperand: DeclReferenceExprSyntax(baseName: .identifier("\(identifier)CallCount")),
            operator: BinaryOperatorExprSyntax(operator: .binaryOperator("+=")),
            rightOperand: IntegerLiteralExprSyntax(literal: .integerLiteral("1"))
        )
        statements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(incrementStmt))))

        // Record call arguments
        let argsExpr = Self.buildArgsExpression(parameters: parameters)
        let appendExpr = FunctionCallExprSyntax(
            calledExpression: MemberAccessExprSyntax(
                base: DeclReferenceExprSyntax(baseName: .identifier("\(identifier)CallArgs")),
                name: .identifier("append")
            ),
            leftParen: .leftParenToken(),
            arguments: LabeledExprListSyntax([
                LabeledExprSyntax(expression: argsExpr)
            ]),
            rightParen: .rightParenToken()
        )
        statements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(appendExpr))))

        // Call handler if set
        let handlerCallStmts = buildHandlerCallStatements(
            identifier: identifier,
            parameters: parameters,
            returnType: returnType,
            isAsync: isAsync,
            isThrows: isThrows,
            hasGenericReturn: hasGenericReturn
        )
        statements.append(contentsOf: handlerCallStmts)

        let body = CodeBlockSyntax(
            leftBrace: .leftBraceToken(trailingTrivia: .newline),
            statements: CodeBlockItemListSyntax(statements),
            rightBrace: .rightBraceToken(leadingTrivia: .newline)
        )

        return FunctionDeclSyntax(
            modifiers: buildModifiers(),
            name: funcDecl.name,
            genericParameterClause: funcDecl.genericParameterClause,
            signature: funcDecl.signature,
            genericWhereClause: funcDecl.genericWhereClause,
            body: body
        )
    }

    private func buildHandlerCallStatements(
        identifier: String,
        parameters: FunctionParameterListSyntax,
        returnType: TypeSyntax?,
        isAsync: Bool,
        isThrows: Bool,
        hasGenericReturn: Bool = false
    ) -> [CodeBlockItemSyntax] {
        let argsExpr = Self.buildArgsExpression(parameters: parameters)
        let handlerCallArgs = parameters.isEmpty ? "" : "\(argsExpr)"

        let hasReturnValue = returnType != nil && returnType?.description != "Void"

        if hasReturnValue {
            let returnTypeStr = returnType?.description ?? "Void"
            let castSuffix = hasGenericReturn ? " as! \(returnTypeStr)" : ""
            let guardStmt = CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: """
guard let _handler = \(identifier)Handler else {
    fatalError("\\(Self.self).\(identifier)Handler is not set")
}
""")))
            let returnStmt = CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: "return \(isThrows ? "try " : "")\(isAsync ? "await " : "")_handler(\(handlerCallArgs))\(castSuffix)")))
            return [guardStmt, returnStmt]
        } else {
            let ifStmt = CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: """
if let _handler = \(identifier)Handler {
    \(isThrows ? "try " : "")\(isAsync ? "await " : "")_handler(\(handlerCallArgs))
}
""")))
            return [ifStmt]
        }
    }
}
