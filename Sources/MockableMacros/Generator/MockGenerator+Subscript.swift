import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Subscript Mock Generation

extension MockGenerator {
    func generateSubscriptMock(
        _ subscriptDecl: SubscriptDeclSyntax
    ) -> [MemberBlockItemSyntax] {
        var members: [MemberBlockItemSyntax] = []

        let parameters = subscriptDecl.parameterClause.parameters
        let returnType = subscriptDecl.returnClause.type
        let genericParamNames = Self.extractGenericParameterNames(from: subscriptDecl)
        let isGetOnly = Self.isGetOnlySubscript(subscriptDecl)
        let suffix = Self.subscriptIdentifierSuffix(from: subscriptDecl)
        let getterEffects = Self.effectfulSubscriptGetter(subscriptDecl)?.effectSpecifiers

        let callCountProperty = generateSubscriptStorageProperty(
            propertyName: MockNaming.callCount(MockNaming.subscriptIdentifier(suffix: suffix)),
            type: TypeSyntax(stringLiteral: "Int"),
            initializer: ExprSyntax(IntegerLiteralExprSyntax(literal: .integerLiteral("0"))),
            usesLockBasedStorage: usesInstanceStorageLock
        )
        members.append(MemberBlockItemSyntax(decl: callCountProperty))

        let tupleType = Self.buildCallArgsTupleType(parameters: parameters, genericParamNames: genericParamNames)
        let callArgsProperty = generateSubscriptStorageProperty(
            propertyName: MockNaming.callArgs(MockNaming.subscriptIdentifier(suffix: suffix)),
            type: TypeSyntax(ArrayTypeSyntax(element: tupleType)),
            initializer: ExprSyntax(ArrayExprSyntax(elements: ArrayElementListSyntax([]))),
            usesLockBasedStorage: usesInstanceStorageLock
        )
        members.append(MemberBlockItemSyntax(decl: callArgsProperty))

        let getterClosureType = buildSubscriptGetterClosureType(
            parameters: parameters,
            returnType: returnType,
            genericParamNames: genericParamNames,
            effects: getterEffects
        )
        let handlerProperty = generateSubscriptStorageProperty(
            propertyName: MockNaming.handler(MockNaming.subscriptIdentifier(suffix: suffix)),
            type: TypeSyntax(stringLiteral: "(@Sendable \(getterClosureType))?"),
            initializer: ExprSyntax(NilLiteralExprSyntax()),
            usesLockBasedStorage: usesInstanceStorageLock
        )
        members.append(MemberBlockItemSyntax(decl: handlerProperty))

        if !isGetOnly {
            let setterClosureType = buildSubscriptSetterClosureType(
                parameters: parameters,
                returnType: returnType,
                genericParamNames: genericParamNames
            )
            let setHandlerProperty = generateSubscriptStorageProperty(
                propertyName: MockNaming.setHandler(MockNaming.subscriptIdentifier(suffix: suffix)),
                type: TypeSyntax(stringLiteral: "(@Sendable \(setterClosureType))?"),
                initializer: ExprSyntax(NilLiteralExprSyntax()),
                usesLockBasedStorage: usesInstanceStorageLock
            )
            members.append(MemberBlockItemSyntax(decl: setHandlerProperty))
        }

        let mockSubscript = generateSubscriptImplementation(
            subscriptDecl,
            isGetOnly: isGetOnly,
            genericParamNames: genericParamNames,
            suffix: suffix
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
        usesLockBasedStorage: Bool
    ) -> VariableDeclSyntax {
        if usesLockBasedStorage {
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
        suffix: String
    ) -> SubscriptDeclSyntax {
        let parameters = subscriptDecl.parameterClause.parameters
        let returnType = subscriptDecl.returnClause.type
        let hasGenericReturn = Self.typeContainsGeneric(returnType, genericParamNames: genericParamNames)
        let getterEffects = Self.effectfulSubscriptGetter(subscriptDecl)?.effectSpecifiers
        let isAsync = getterEffects?.asyncSpecifier != nil
        let isThrows = getterEffects?.hasThrowsEffect ?? false
        let invokePrefix = "\(isThrows ? "try " : "")\(isAsync ? "await " : "")"
        let errorType = getterEffects?.throwsErrorType?.trimmedDescription

        let getterStatements: [CodeBlockItemSyntax]
        if usesInstanceStorageLock {
            getterStatements = buildLockBasedSubscriptGetterStatements(
                parameters: parameters,
                returnType: returnType,
                hasGenericReturn: hasGenericReturn,
                suffix: suffix,
                invokePrefix: invokePrefix,
                errorType: errorType
            )
        } else {
            getterStatements = buildDirectSubscriptGetterStatements(
                parameters: parameters,
                returnType: returnType,
                hasGenericReturn: hasGenericReturn,
                suffix: suffix,
                invokePrefix: invokePrefix,
                errorType: errorType
            )
        }

        let accessors: AccessorBlockSyntax
        if isGetOnly {
            if let getterEffects {
                // Effectful subscripts must use an explicit `get async/throws` accessor
                // rather than the getter shorthand.
                accessors = AccessorBlockSyntax(
                    accessors: .accessors(AccessorDeclListSyntax([
                        AccessorDeclSyntax(
                            accessorSpecifier: .keyword(.get),
                            effectSpecifiers: getterEffects.trimmed,
                            body: CodeBlockSyntax(statements: CodeBlockItemListSyntax(getterStatements))
                        )
                    ]))
                )
            } else {
                accessors = AccessorBlockSyntax(
                    accessors: .getter(CodeBlockItemListSyntax(getterStatements))
                )
            }
        } else {
            var setterStatements = Self.buildAutoclosureEvaluationStatements(parameters: parameters)
            if usesInstanceStorageLock {
                setterStatements.append(buildLockBasedSubscriptSetHandlerCallStatement(parameters: parameters, suffix: suffix))
            } else {
                setterStatements.append(buildDirectSubscriptSetHandlerCallStatement(parameters: parameters, suffix: suffix))
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
        suffix: String,
        invokePrefix: String = "",
        errorType: String? = nil
    ) -> [CodeBlockItemSyntax] {
        var getterStatements: [CodeBlockItemSyntax] = []
        getterStatements.append(contentsOf: Self.buildAutoclosureEvaluationStatements(parameters: parameters))

        let incrementStmt = InfixOperatorExprSyntax(
            leftOperand: DeclReferenceExprSyntax(baseName: .identifier(MockNaming.callCount(MockNaming.subscriptIdentifier(suffix: suffix)))),
            operator: BinaryOperatorExprSyntax(operator: .binaryOperator("+=")),
            rightOperand: IntegerLiteralExprSyntax(literal: .integerLiteral("1"))
        )
        getterStatements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(incrementStmt))))

        let argsExpr = Self.buildCallArgsExpression(parameters: parameters)
        let appendExpr = FunctionCallExprSyntax(
            calledExpression: MemberAccessExprSyntax(
                base: DeclReferenceExprSyntax(baseName: .identifier(MockNaming.callArgs(MockNaming.subscriptIdentifier(suffix: suffix)))),
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
            suffix: suffix,
            invokePrefix: invokePrefix,
            errorType: errorType
        ))

        return getterStatements
    }

    private func buildSubscriptHandlerCallStatements(
        parameters: FunctionParameterListSyntax,
        returnType: TypeSyntax,
        hasGenericReturn: Bool,
        suffix: String,
        invokePrefix: String = "",
        errorType: String? = nil
    ) -> [CodeBlockItemSyntax] {
        let handlerCallArgs = buildHandlerCallArguments(parameters: parameters)

        let returnTypeStr = returnType.description
        let castSuffix = hasGenericReturn ? " as! \(returnTypeStr)" : ""
        let elseBody = Self.defaultReturnStatement(for: returnType)
            ?? "fatalError(\"\\(Self.self).\(MockNaming.handler(MockNaming.subscriptIdentifier(suffix: suffix))) is not set\")"
        let guardStmt = CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: """
guard let _handler = \(MockNaming.handler(MockNaming.subscriptIdentifier(suffix: suffix))) else {
    \(elseBody)
}
""")))
        let returnLine = "return \(invokePrefix)_handler(\(handlerCallArgs))\(castSuffix)"
        let returnStmt = errorType.map { Self.buildTypedThrowsCatch(innerLines: [returnLine], errorType: $0) }
            ?? CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: returnLine)))
        return [guardStmt, returnStmt]
    }

    private func buildDirectSubscriptSetHandlerCallStatement(
        parameters: FunctionParameterListSyntax,
        suffix: String
    ) -> CodeBlockItemSyntax {
        let handlerCallArgs: String
        if parameters.isEmpty {
            handlerCallArgs = "newValue"
        } else {
            handlerCallArgs = "\(buildHandlerCallArguments(parameters: parameters)), newValue"
        }

        return CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: """
if let _handler = \(MockNaming.setHandler(MockNaming.subscriptIdentifier(suffix: suffix))) {
    _handler(\(handlerCallArgs))
}
""")))
    }

    private func buildLockBasedSubscriptGetterStatements(
        parameters: FunctionParameterListSyntax,
        returnType: TypeSyntax,
        hasGenericReturn: Bool,
        suffix: String,
        invokePrefix: String = "",
        errorType: String? = nil
    ) -> [CodeBlockItemSyntax] {
        let argsExpr = Self.buildCallArgsExpression(parameters: parameters)

        var statements: [CodeBlockItemSyntax] = []
        // Evaluate @autoclosure arguments before taking the lock so user-supplied
        // expressions never run while the storage lock is held.
        statements.append(contentsOf: Self.buildAutoclosureEvaluationStatements(parameters: parameters))
        let recordCallStmt = CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: """
_storage.withLock { storage in
    storage.\(MockNaming.callCount(MockNaming.subscriptIdentifier(suffix: suffix))) += 1
    storage.\(MockNaming.callArgs(MockNaming.subscriptIdentifier(suffix: suffix))).append(\(argsExpr))
}
""")))
        statements.append(recordCallStmt)
        let getHandlerStmt = CodeBlockItemSyntax(item: .decl(DeclSyntax(stringLiteral: "let _handler = _storage.withLock { $0.\(MockNaming.handler(MockNaming.subscriptIdentifier(suffix: suffix))) }")))
        statements.append(getHandlerStmt)

        let handlerCallArgs = buildHandlerCallArguments(parameters: parameters)
        let returnTypeStr = returnType.description
        let castSuffix = hasGenericReturn ? " as! \(returnTypeStr)" : ""

        let elseBody = Self.defaultReturnStatement(for: returnType)
            ?? "fatalError(\"\\(Self.self).\(MockNaming.handler(MockNaming.subscriptIdentifier(suffix: suffix))) is not set\")"
        let guardStmt = CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: """
guard let _handler else {
    \(elseBody)
}
""")))
        let returnLine = "return \(invokePrefix)_handler(\(handlerCallArgs))\(castSuffix)"
        let returnStmt = errorType.map { Self.buildTypedThrowsCatch(innerLines: [returnLine], errorType: $0) }
            ?? CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: returnLine)))

        statements.append(guardStmt)
        statements.append(returnStmt)
        return statements
    }

    private func buildLockBasedSubscriptSetHandlerCallStatement(
        parameters: FunctionParameterListSyntax,
        suffix: String
    ) -> CodeBlockItemSyntax {
        let handlerCallArgs: String
        if parameters.isEmpty {
            handlerCallArgs = "newValue"
        } else {
            handlerCallArgs = "\(buildHandlerCallArguments(parameters: parameters)), newValue"
        }

        return CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: """
if let _handler = _storage.withLock({ $0.\(MockNaming.setHandler(MockNaming.subscriptIdentifier(suffix: suffix))) }) {
    _handler(\(handlerCallArgs))
}
""")))
    }

    /// The parameter-type portion of a subscript handler closure.
    /// Callers handle the empty-parameter case separately (subscripts always have >= 1 param,
    /// but the closure-type builders keep the defensive branch).
    /// - multiple parameters (>= 2): `"Int, Int"` (individual parameters)
    /// - single parameter:           `"Int"`
    private func subscriptHandlerParameterList(
        parameters: FunctionParameterListSyntax,
        genericParamNames: Set<String>
    ) -> String {
        if parameters.count >= 2 {
            return Self.buildSeparateParameterTypeList(parameters: parameters, genericParamNames: genericParamNames)
        }
        return Self.buildParameterTupleType(parameters: parameters, genericParamNames: genericParamNames).description
    }

    /// The `get` accessor of a subscript when it carries `async`/`throws` effects
    /// (e.g. `subscript(i: Int) -> T { get async throws }`), or `nil` otherwise.
    static func effectfulSubscriptGetter(_ subscriptDecl: SubscriptDeclSyntax) -> AccessorDeclSyntax? {
        guard let accessorBlock = subscriptDecl.accessorBlock,
              case .accessors(let accessors) = accessorBlock.accessors else {
            return nil
        }
        return accessors.first { accessor in
            accessor.accessorSpecifier.tokenKind == .keyword(.get) && accessor.effectSpecifiers != nil
        }
    }

    func buildSubscriptGetterClosureType(
        parameters: FunctionParameterListSyntax,
        returnType: TypeSyntax,
        genericParamNames: Set<String>,
        effects: AccessorEffectSpecifiersSyntax? = nil
    ) -> String {
        let erasedReturnType = Self.eraseGenericTypes(in: returnType, genericParamNames: genericParamNames)
        let returnTypeStr = erasedReturnType.description
        // The handler is untyped-throwing even for a typed-throws accessor
        // (`get throws(E)`) — the generated getter re-throws the typed error via a
        // `catch` — so a typed error type is dropped here.
        var effectsText = ""
        if effects?.asyncSpecifier != nil {
            effectsText += " async"
        }
        if effects?.hasThrowsEffect == true {
            effectsText += " throws"
        }

        if parameters.isEmpty {
            return "()\(effectsText) -> \(returnTypeStr)"
        }
        let paramList = subscriptHandlerParameterList(parameters: parameters, genericParamNames: genericParamNames)
        return "(\(paramList))\(effectsText) -> \(returnTypeStr)"
    }

    func buildSubscriptSetterClosureType(
        parameters: FunctionParameterListSyntax,
        returnType: TypeSyntax,
        genericParamNames: Set<String>
    ) -> String {
        let erasedReturnType = Self.eraseGenericTypes(in: returnType, genericParamNames: genericParamNames)
        let returnTypeStr = erasedReturnType.description

        if parameters.isEmpty {
            return "(\(returnTypeStr)) -> Void"
        }
        let paramList = subscriptHandlerParameterList(parameters: parameters, genericParamNames: genericParamNames)
        return "(\(paramList), \(returnTypeStr)) -> Void"
    }
}
