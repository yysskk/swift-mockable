import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Subscript Mock Generation

extension MockGenerator {
    func generateSubscriptMock(
        _ subscriptDecl: SubscriptDeclSyntax,
        storageStrategy: StorageStrategy
    ) -> [MemberBlockItemSyntax] {
        var members: [MemberBlockItemSyntax] = []

        let parameters = subscriptDecl.parameterClause.parameters
        let returnType = subscriptDecl.returnClause.type
        let genericParamNames = Self.extractGenericParameterNames(from: subscriptDecl)
        let isGetOnly = Self.isGetOnlySubscript(subscriptDecl)
        let suffix = Self.subscriptIdentifierSuffix(from: subscriptDecl)

        let callCountProperty = generateSubscriptStorageProperty(
            propertyName: "subscript\(suffix)CallCount",
            type: TypeSyntax(stringLiteral: "Int"),
            initializer: ExprSyntax(IntegerLiteralExprSyntax(literal: .integerLiteral("0"))),
            storageStrategy: storageStrategy
        )
        members.append(MemberBlockItemSyntax(decl: callCountProperty))

        let tupleType = Self.buildParameterTupleType(parameters: parameters, genericParamNames: genericParamNames)
        let callArgsProperty = generateSubscriptStorageProperty(
            propertyName: "subscript\(suffix)CallArgs",
            type: TypeSyntax(ArrayTypeSyntax(element: tupleType)),
            initializer: ExprSyntax(ArrayExprSyntax(elements: ArrayElementListSyntax([]))),
            storageStrategy: storageStrategy
        )
        members.append(MemberBlockItemSyntax(decl: callArgsProperty))

        let getterClosureType = buildSubscriptGetterClosureType(
            parameters: parameters,
            returnType: returnType,
            genericParamNames: genericParamNames
        )
        let handlerProperty = generateSubscriptStorageProperty(
            propertyName: "subscript\(suffix)Handler",
            type: TypeSyntax(stringLiteral: "(@Sendable \(getterClosureType))?"),
            initializer: ExprSyntax(NilLiteralExprSyntax()),
            storageStrategy: storageStrategy
        )
        members.append(MemberBlockItemSyntax(decl: handlerProperty))

        if !isGetOnly {
            let setterClosureType = buildSubscriptSetterClosureType(
                parameters: parameters,
                returnType: returnType,
                genericParamNames: genericParamNames
            )
            let setHandlerProperty = generateSubscriptStorageProperty(
                propertyName: "subscript\(suffix)SetHandler",
                type: TypeSyntax(stringLiteral: "(@Sendable \(setterClosureType))?"),
                initializer: ExprSyntax(NilLiteralExprSyntax()),
                storageStrategy: storageStrategy
            )
            members.append(MemberBlockItemSyntax(decl: setHandlerProperty))
        }

        let mockSubscript = generateSubscriptImplementation(
            subscriptDecl,
            isGetOnly: isGetOnly,
            genericParamNames: genericParamNames,
            suffix: suffix,
            storageStrategy: storageStrategy
        )
        members.append(MemberBlockItemSyntax(decl: mockSubscript))

        return members
    }

    static func isGetOnlySubscript(_ subscriptDecl: SubscriptDeclSyntax) -> Bool {
        guard let accessorBlock = subscriptDecl.accessorBlock else {
            return true
        }

        switch accessorBlock.accessors {
        case .getter:
            return true
        case .accessors(let accessors):
            let hasGetter = accessors.contains { $0.accessorSpecifier.tokenKind == .keyword(.get) }
            let hasSetter = accessors.contains { $0.accessorSpecifier.tokenKind == .keyword(.set) }
            return hasGetter && !hasSetter
        }
    }

    static func extractGenericParameterNames(from subscriptDecl: SubscriptDeclSyntax) -> Set<String> {
        guard let genericClause = subscriptDecl.genericParameterClause else {
            return []
        }
        return Set(genericClause.parameters.map { $0.name.text })
    }

    /// Generates a unique suffix based on parameter types to distinguish overloaded subscripts.
    static func subscriptIdentifierSuffix(from subscriptDecl: SubscriptDeclSyntax) -> String {
        let parameters = subscriptDecl.parameterClause.parameters
        if parameters.isEmpty {
            return ""
        }

        let typeNames = parameters.map { param -> String in
            let typeName = param.type.trimmedDescription
            return sanitizeTypeName(typeName)
        }

        return typeNames.joined()
    }

    private func generateSubscriptStorageProperty(
        propertyName: String,
        type: TypeSyntax,
        initializer: ExprSyntax,
        storageStrategy: StorageStrategy
    ) -> VariableDeclSyntax {
        if storageStrategy.isLockBased {
            return VariableDeclSyntax(
                modifiers: buildModifiers(additional: storageBackedMemberModifiers()),
                bindingSpecifier: .keyword(.var),
                bindings: PatternBindingListSyntax([
                    PatternBindingSyntax(
                        pattern: IdentifierPatternSyntax(identifier: .identifier(propertyName)),
                        typeAnnotation: TypeAnnotationSyntax(type: type),
                        accessorBlock: AccessorBlockSyntax(
                            accessors: .accessors(AccessorDeclListSyntax([
                                AccessorDeclSyntax(
                                    accessorSpecifier: .keyword(.get),
                                    body: CodeBlockSyntax(
                                        statements: CodeBlockItemListSyntax([
                                            CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.\(propertyName) }")))
                                        ])
                                    )
                                ),
                                AccessorDeclSyntax(
                                    accessorSpecifier: .keyword(.set),
                                    body: CodeBlockSyntax(
                                        statements: CodeBlockItemListSyntax([
                                            CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.\(propertyName) = newValue }")))
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
                    pattern: IdentifierPatternSyntax(identifier: .identifier(propertyName)),
                    typeAnnotation: TypeAnnotationSyntax(type: type),
                    initializer: InitializerClauseSyntax(value: initializer)
                )
            ])
        )
    }

    private func generateSubscriptImplementation(
        _ subscriptDecl: SubscriptDeclSyntax,
        isGetOnly: Bool,
        genericParamNames: Set<String>,
        suffix: String,
        storageStrategy: StorageStrategy
    ) -> SubscriptDeclSyntax {
        let parameters = subscriptDecl.parameterClause.parameters
        let returnType = subscriptDecl.returnClause.type
        let hasGenericReturn = Self.typeContainsGeneric(returnType, genericParamNames: genericParamNames)

        let getterStatements: [CodeBlockItemSyntax]
        if storageStrategy.isLockBased {
            getterStatements = buildLockBasedSubscriptGetterStatements(
                parameters: parameters,
                returnType: returnType,
                hasGenericReturn: hasGenericReturn,
                suffix: suffix
            )
        } else {
            getterStatements = buildDirectSubscriptGetterStatements(
                parameters: parameters,
                returnType: returnType,
                hasGenericReturn: hasGenericReturn,
                suffix: suffix
            )
        }

        let accessors: AccessorBlockSyntax
        if isGetOnly {
            accessors = AccessorBlockSyntax(
                accessors: .getter(CodeBlockItemListSyntax(getterStatements))
            )
        } else {
            let setterStatements: [CodeBlockItemSyntax]
            if storageStrategy.isLockBased {
                setterStatements = [buildLockBasedSubscriptSetHandlerCallStatement(parameters: parameters, suffix: suffix)]
            } else {
                setterStatements = [buildDirectSubscriptSetHandlerCallStatement(parameters: parameters, suffix: suffix)]
            }

            accessors = AccessorBlockSyntax(
                accessors: .accessors(AccessorDeclListSyntax([
                    AccessorDeclSyntax(
                        accessorSpecifier: .keyword(.get),
                        body: CodeBlockSyntax(statements: CodeBlockItemListSyntax(getterStatements))
                    ),
                    AccessorDeclSyntax(
                        accessorSpecifier: .keyword(.set),
                        body: CodeBlockSyntax(statements: CodeBlockItemListSyntax(setterStatements))
                    )
                ]))
            )
        }

        return SubscriptDeclSyntax(
            modifiers: buildModifiers(),
            genericParameterClause: subscriptDecl.genericParameterClause,
            parameterClause: subscriptDecl.parameterClause,
            returnClause: subscriptDecl.returnClause,
            genericWhereClause: subscriptDecl.genericWhereClause,
            accessorBlock: accessors
        )
    }

    private func buildDirectSubscriptGetterStatements(
        parameters: FunctionParameterListSyntax,
        returnType: TypeSyntax,
        hasGenericReturn: Bool,
        suffix: String
    ) -> [CodeBlockItemSyntax] {
        var getterStatements: [CodeBlockItemSyntax] = []

        let incrementStmt = InfixOperatorExprSyntax(
            leftOperand: DeclReferenceExprSyntax(baseName: .identifier("subscript\(suffix)CallCount")),
            operator: BinaryOperatorExprSyntax(operator: .binaryOperator("+=")),
            rightOperand: IntegerLiteralExprSyntax(literal: .integerLiteral("1"))
        )
        getterStatements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(incrementStmt))))

        let argsExpr = Self.buildArgsExpression(parameters: parameters)
        let appendExpr = FunctionCallExprSyntax(
            calledExpression: MemberAccessExprSyntax(
                base: DeclReferenceExprSyntax(baseName: .identifier("subscript\(suffix)CallArgs")),
                name: .identifier("append")
            ),
            leftParen: .leftParenToken(),
            arguments: LabeledExprListSyntax([
                LabeledExprSyntax(expression: argsExpr)
            ]),
            rightParen: .rightParenToken()
        )
        getterStatements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(appendExpr))))

        getterStatements.append(contentsOf: buildSubscriptHandlerCallStatements(
            parameters: parameters,
            returnType: returnType,
            hasGenericReturn: hasGenericReturn,
            suffix: suffix
        ))

        return getterStatements
    }

    private func buildSubscriptHandlerCallStatements(
        parameters: FunctionParameterListSyntax,
        returnType: TypeSyntax,
        hasGenericReturn: Bool,
        suffix: String
    ) -> [CodeBlockItemSyntax] {
        let argsExpr = Self.buildArgsExpression(parameters: parameters)
        let handlerCallArgs = parameters.isEmpty ? "" : "\(argsExpr)"

        let returnTypeStr = returnType.description
        let castSuffix = hasGenericReturn ? " as! \(returnTypeStr)" : ""
        let guardStmt = CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: """
guard let _handler = subscript\(suffix)Handler else {
    fatalError("\\(Self.self).subscript\(suffix)Handler is not set")
}
""")))
        let returnStmt = CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: "return _handler(\(handlerCallArgs))\(castSuffix)")))
        return [guardStmt, returnStmt]
    }

    private func buildDirectSubscriptSetHandlerCallStatement(
        parameters: FunctionParameterListSyntax,
        suffix: String
    ) -> CodeBlockItemSyntax {
        let argsExpr = Self.buildArgsExpression(parameters: parameters)
        let handlerCallArgs: String
        if parameters.isEmpty {
            handlerCallArgs = "newValue"
        } else {
            handlerCallArgs = "\(argsExpr), newValue"
        }

        return CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: """
if let _handler = subscript\(suffix)SetHandler {
    _handler(\(handlerCallArgs))
}
""")))
    }

    private func buildLockBasedSubscriptGetterStatements(
        parameters: FunctionParameterListSyntax,
        returnType: TypeSyntax,
        hasGenericReturn: Bool,
        suffix: String
    ) -> [CodeBlockItemSyntax] {
        let argsExpr = Self.buildArgsExpression(parameters: parameters)

        var statements: [CodeBlockItemSyntax] = []
        let recordCallStmt = CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: """
_storage.withLock { storage in
    storage.subscript\(suffix)CallCount += 1
    storage.subscript\(suffix)CallArgs.append(\(argsExpr))
}
""")))
        statements.append(recordCallStmt)
        let getHandlerStmt = CodeBlockItemSyntax(item: .decl(DeclSyntax(stringLiteral: "let _handler = _storage.withLock { $0.subscript\(suffix)Handler }")))
        statements.append(getHandlerStmt)

        let handlerCallArgs = parameters.isEmpty ? "" : "\(argsExpr)"
        let returnTypeStr = returnType.description
        let castSuffix = hasGenericReturn ? " as! \(returnTypeStr)" : ""

        let guardStmt = CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: """
guard let _handler else {
    fatalError("\\(Self.self).subscript\(suffix)Handler is not set")
}
""")))
        let returnStmt = CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: "return _handler(\(handlerCallArgs))\(castSuffix)")))

        statements.append(guardStmt)
        statements.append(returnStmt)
        return statements
    }

    private func buildLockBasedSubscriptSetHandlerCallStatement(
        parameters: FunctionParameterListSyntax,
        suffix: String
    ) -> CodeBlockItemSyntax {
        let argsExpr = Self.buildArgsExpression(parameters: parameters)
        let handlerCallArgs: String
        if parameters.isEmpty {
            handlerCallArgs = "newValue"
        } else {
            handlerCallArgs = "\(argsExpr), newValue"
        }

        return CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: """
if let _handler = _storage.withLock({ $0.subscript\(suffix)SetHandler }) {
    _handler(\(handlerCallArgs))
}
""")))
    }

    private func buildSubscriptGetterClosureType(
        parameters: FunctionParameterListSyntax,
        returnType: TypeSyntax,
        genericParamNames: Set<String>
    ) -> String {
        let paramTupleType = Self.buildParameterTupleType(
            parameters: parameters,
            genericParamNames: genericParamNames
        )
        let erasedReturnType = Self.eraseGenericTypes(in: returnType, genericParamNames: genericParamNames)
        let returnTypeStr = erasedReturnType.description

        return parameters.isEmpty ? "() -> \(returnTypeStr)" : "(\(paramTupleType.description)) -> \(returnTypeStr)"
    }

    private func buildSubscriptSetterClosureType(
        parameters: FunctionParameterListSyntax,
        returnType: TypeSyntax,
        genericParamNames: Set<String>
    ) -> String {
        let paramTupleType = Self.buildParameterTupleType(
            parameters: parameters,
            genericParamNames: genericParamNames
        )
        let erasedReturnType = Self.eraseGenericTypes(in: returnType, genericParamNames: genericParamNames)
        let returnTypeStr = erasedReturnType.description

        if parameters.isEmpty {
            return "(\(returnTypeStr)) -> Void"
        }
        return "(\(paramTupleType.description), \(returnTypeStr)) -> Void"
    }
}
