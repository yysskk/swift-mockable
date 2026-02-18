import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Function Mock Generation

extension MockGenerator {
    func generateFunctionMock(
        _ funcDecl: FunctionDeclSyntax,
        suffix: String = "",
        storageStrategy: StorageStrategy
    ) -> [MemberBlockItemSyntax] {
        var members: [MemberBlockItemSyntax] = []

        let funcName = funcDecl.name.text
        let identifier = suffix.isEmpty ? funcName : "\(funcName)\(suffix)"
        let parameters = funcDecl.signature.parameterClause.parameters
        let returnType = funcDecl.signature.returnClause?.type
        let isAsync = funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil
        let isThrows = funcDecl.signature.effectSpecifiers?.hasThrowsEffect ?? false
        let genericParamNames = Self.extractGenericParameterNames(from: funcDecl)

        let callCountProperty = generateFunctionStorageProperty(
            identifier: identifier,
            propertyName: "CallCount",
            type: TypeSyntax(stringLiteral: "Int"),
            initializer: ExprSyntax(IntegerLiteralExprSyntax(literal: .integerLiteral("0"))),
            storageStrategy: storageStrategy
        )
        members.append(MemberBlockItemSyntax(decl: callCountProperty))

        let tupleType = Self.buildParameterTupleType(parameters: parameters, genericParamNames: genericParamNames)
        let callArgsProperty = generateFunctionStorageProperty(
            identifier: identifier,
            propertyName: "CallArgs",
            type: TypeSyntax(ArrayTypeSyntax(element: tupleType)),
            initializer: ExprSyntax(ArrayExprSyntax(elements: ArrayElementListSyntax([]))),
            storageStrategy: storageStrategy
        )
        members.append(MemberBlockItemSyntax(decl: callArgsProperty))

        let closureType = buildFunctionClosureType(
            parameters: parameters,
            returnType: returnType,
            isAsync: isAsync,
            isThrows: isThrows,
            genericParamNames: genericParamNames
        )
        let handlerProperty = generateFunctionStorageProperty(
            identifier: identifier,
            propertyName: "Handler",
            type: TypeSyntax(stringLiteral: "(@Sendable \(closureType))?"),
            initializer: ExprSyntax(NilLiteralExprSyntax()),
            storageStrategy: storageStrategy
        )
        members.append(MemberBlockItemSyntax(decl: handlerProperty))

        let mockFunction = generateMockFunction(
            funcDecl,
            identifier: identifier,
            genericParamNames: genericParamNames,
            storageStrategy: storageStrategy
        )
        members.append(MemberBlockItemSyntax(decl: mockFunction))

        return members
    }

    private func generateFunctionStorageProperty(
        identifier: String,
        propertyName: String,
        type: TypeSyntax,
        initializer: ExprSyntax,
        storageStrategy: StorageStrategy
    ) -> VariableDeclSyntax {
        let fullName = "\(identifier)\(propertyName)"

        if storageStrategy.isLockBased {
            return VariableDeclSyntax(
                modifiers: buildModifiers(additional: storageBackedMemberModifiers()),
                bindingSpecifier: .keyword(.var),
                bindings: PatternBindingListSyntax([
                    PatternBindingSyntax(
                        pattern: IdentifierPatternSyntax(identifier: .identifier(fullName)),
                        typeAnnotation: TypeAnnotationSyntax(type: type),
                        accessorBlock: AccessorBlockSyntax(
                            accessors: .accessors(AccessorDeclListSyntax([
                                AccessorDeclSyntax(
                                    accessorSpecifier: .keyword(.get),
                                    body: CodeBlockSyntax(
                                        statements: CodeBlockItemListSyntax([
                                            CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.\(fullName) }")))
                                        ])
                                    )
                                ),
                                AccessorDeclSyntax(
                                    accessorSpecifier: .keyword(.set),
                                    body: CodeBlockSyntax(
                                        statements: CodeBlockItemListSyntax([
                                            CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.\(fullName) = newValue }")))
                                        ])
                                    )
                                )
                            ]))
                        )
                    )
                ])
            )
        }

        return VariableDeclSyntax(
            modifiers: buildModifiers(),
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier(fullName)),
                    typeAnnotation: TypeAnnotationSyntax(type: type),
                    initializer: InitializerClauseSyntax(value: initializer)
                )
            ])
        )
    }

    private func generateMockFunction(
        _ funcDecl: FunctionDeclSyntax,
        identifier: String,
        genericParamNames: Set<String>,
        storageStrategy: StorageStrategy
    ) -> FunctionDeclSyntax {
        let parameters = funcDecl.signature.parameterClause.parameters
        let returnType = funcDecl.signature.returnClause?.type
        let isAsync = funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil
        let isThrows = funcDecl.signature.effectSpecifiers?.hasThrowsEffect ?? false
        let hasGenericReturn = returnType.map { Self.typeContainsGeneric($0, genericParamNames: genericParamNames) } ?? false

        let body: CodeBlockSyntax
        if storageStrategy.isLockBased {
            body = buildLockBasedFunctionBody(
                identifier: identifier,
                parameters: parameters,
                returnType: returnType,
                isAsync: isAsync,
                isThrows: isThrows,
                hasGenericReturn: hasGenericReturn,
                genericParamNames: genericParamNames
            )
        } else {
            body = buildDirectFunctionBody(
                identifier: identifier,
                parameters: parameters,
                returnType: returnType,
                isAsync: isAsync,
                isThrows: isThrows,
                hasGenericReturn: hasGenericReturn
            )
        }

        return FunctionDeclSyntax(
            modifiers: buildModifiers(),
            name: funcDecl.name,
            genericParameterClause: funcDecl.genericParameterClause,
            signature: funcDecl.signature,
            genericWhereClause: funcDecl.genericWhereClause,
            body: body
        )
    }

    private func buildDirectFunctionBody(
        identifier: String,
        parameters: FunctionParameterListSyntax,
        returnType: TypeSyntax?,
        isAsync: Bool,
        isThrows: Bool,
        hasGenericReturn: Bool
    ) -> CodeBlockSyntax {
        var statements: [CodeBlockItemSyntax] = []

        let incrementStmt = InfixOperatorExprSyntax(
            leftOperand: DeclReferenceExprSyntax(baseName: .identifier("\(identifier)CallCount")),
            operator: BinaryOperatorExprSyntax(operator: .binaryOperator("+=")),
            rightOperand: IntegerLiteralExprSyntax(literal: .integerLiteral("1"))
        )
        statements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(incrementStmt))))

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

        let handlerCallStmts = buildHandlerCallStatements(
            identifier: identifier,
            parameters: parameters,
            returnType: returnType,
            isAsync: isAsync,
            isThrows: isThrows,
            hasGenericReturn: hasGenericReturn
        )
        statements.append(contentsOf: handlerCallStmts)

        return CodeBlockSyntax(
            leftBrace: .leftBraceToken(trailingTrivia: .newline),
            statements: CodeBlockItemListSyntax(statements),
            rightBrace: .rightBraceToken(leadingTrivia: .newline)
        )
    }

    private func buildLockBasedFunctionBody(
        identifier: String,
        parameters: FunctionParameterListSyntax,
        returnType: TypeSyntax?,
        isAsync: Bool,
        isThrows: Bool,
        hasGenericReturn: Bool,
        genericParamNames: Set<String>
    ) -> CodeBlockSyntax {
        let argsExpr = Self.buildArgsExpression(parameters: parameters)
        let hasReturnValue = returnType != nil && returnType?.description != "Void"
        let handlerCallArgs = parameters.isEmpty ? "" : "\(argsExpr)"

        let closureType = buildFunctionClosureType(
            parameters: parameters,
            returnType: returnType,
            isAsync: isAsync,
            isThrows: isThrows,
            genericParamNames: genericParamNames
        )

        var statements: [CodeBlockItemSyntax] = []
        let withLockStmt = CodeBlockItemSyntax(item: .decl(DeclSyntax(stringLiteral: """
let _handler = _storage.withLock { storage -> (@Sendable \(closureType))? in
    storage.\(identifier)CallCount += 1
    storage.\(identifier)CallArgs.append(\(argsExpr))
    return storage.\(identifier)Handler
}
""")))
        statements.append(withLockStmt)

        if hasReturnValue {
            let returnTypeStr = returnType?.description ?? "Void"
            let castSuffix = hasGenericReturn ? " as! \(returnTypeStr)" : ""
            let guardStmt = CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: """
guard let _handler else {
    fatalError("\\(Self.self).\(identifier)Handler is not set")
}
""")))
            statements.append(guardStmt)
            let returnStmt = CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: "return \(isThrows ? "try " : "")\(isAsync ? "await " : "")_handler(\(handlerCallArgs))\(castSuffix)")))
            statements.append(returnStmt)
        } else {
            let ifStmt = CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: """
if let _handler {
\(isThrows ? "try " : "")\(isAsync ? "await " : "")_handler(\(handlerCallArgs))
}
""")))
            statements.append(ifStmt)
        }

        return CodeBlockSyntax(
            leftBrace: .leftBraceToken(trailingTrivia: .newline),
            statements: CodeBlockItemListSyntax(statements),
            rightBrace: .rightBraceToken(leadingTrivia: .newline)
        )
    }

    private func buildFunctionClosureType(
        parameters: FunctionParameterListSyntax,
        returnType: TypeSyntax?,
        isAsync: Bool,
        isThrows: Bool,
        genericParamNames: Set<String>
    ) -> String {
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
        return closureType
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
