import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Subscript Mock Generation

extension MockGenerator {
    /// Generates the members that mock a subscript requirement: the call-count and
    /// captured-index properties, a get handler, a set handler (for get-set subscripts),
    /// and the subscript witness. The identifier suffix encodes the index and element
    /// types so overloaded subscripts get distinct members.
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

        let callCountProperty = generateTrackingStorageProperty(
            name: MockNaming.callCount(MockNaming.subscriptIdentifier(suffix: suffix)),
            type: TypeSyntax(stringLiteral: "Int"),
            initializer: ExprSyntax(IntegerLiteralExprSyntax(literal: .integerLiteral("0"))),
            isTypeMember: false
        )
        members.append(MemberBlockItemSyntax(decl: callCountProperty))

        let tupleType = Self.buildCallArgsTupleType(parameters: parameters, genericParamNames: genericParamNames)
        let callArgsProperty = generateTrackingStorageProperty(
            name: MockNaming.callArgs(MockNaming.subscriptIdentifier(suffix: suffix)),
            type: TypeSyntax(ArrayTypeSyntax(element: tupleType)),
            initializer: ExprSyntax(ArrayExprSyntax(elements: ArrayElementListSyntax([]))),
            isTypeMember: false
        )
        members.append(MemberBlockItemSyntax(decl: callArgsProperty))

        let getterClosureType = buildSubscriptGetterClosureType(
            parameters: parameters,
            returnType: returnType,
            genericParamNames: genericParamNames,
            effects: getterEffects
        )
        let handlerProperty = generateTrackingStorageProperty(
            name: MockNaming.handler(MockNaming.subscriptIdentifier(suffix: suffix)),
            type: TypeSyntax(stringLiteral: "(@Sendable \(getterClosureType))?"),
            initializer: ExprSyntax(NilLiteralExprSyntax()),
            isTypeMember: false
        )
        members.append(MemberBlockItemSyntax(decl: handlerProperty))

        if !isGetOnly {
            let setterClosureType = buildSubscriptSetterClosureType(
                parameters: parameters,
                returnType: returnType,
                genericParamNames: genericParamNames
            )
            let setHandlerProperty = generateTrackingStorageProperty(
                name: MockNaming.setHandler(MockNaming.subscriptIdentifier(suffix: suffix)),
                type: TypeSyntax(stringLiteral: "(@Sendable \(setterClosureType))?"),
                initializer: ExprSyntax(NilLiteralExprSyntax()),
                isTypeMember: false
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

    /// A subscript requirement with no accessor block (`subscript(i: Int) -> Int`)
    /// is get-only, hence the `true` default.
    static func isGetOnlySubscript(_ subscriptDecl: SubscriptDeclSyntax) -> Bool {
        isGetOnly(subscriptDecl.accessorBlock, defaultWhenAbsent: true)
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

        getterStatements.append(contentsOf: Self.makeCallRecordingStatements(
            identifier: MockNaming.subscriptIdentifier(suffix: suffix),
            parameters: parameters
        ))

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

    /// Builds the unset-handler guard and the handler invocation shared by the direct
    /// and lock-based subscript getters, which differ only in how `_handler` is bound.
    private func buildGuardedSubscriptHandlerReturn(
        guardBinding: String,
        parameters: FunctionParameterListSyntax,
        returnType: TypeSyntax,
        hasGenericReturn: Bool,
        suffix: String,
        invokePrefix: String,
        errorType: String?
    ) -> [CodeBlockItemSyntax] {
        let returnTypeStr = Self.castTargetType(for: returnType)
        let guardStmt = Self.makeUnsetHandlerGuard(
            binding: guardBinding,
            elseBody: Self.unsetHandlerElseBody(
                returnType: returnType,
                handlerName: MockNaming.handler(MockNaming.subscriptIdentifier(suffix: suffix))
            )
        )
        let returnStmt = Self.makeHandlerReturnStatement(
            invokePrefix: invokePrefix,
            handlerCallArgs: buildHandlerCallArguments(parameters: parameters),
            castSuffix: hasGenericReturn ? " as! \(returnTypeStr)" : "",
            errorType: errorType
        )
        return [guardStmt, returnStmt]
    }

    private func buildSubscriptHandlerCallStatements(
        parameters: FunctionParameterListSyntax,
        returnType: TypeSyntax,
        hasGenericReturn: Bool,
        suffix: String,
        invokePrefix: String = "",
        errorType: String? = nil
    ) -> [CodeBlockItemSyntax] {
        buildGuardedSubscriptHandlerReturn(
            guardBinding: "_handler = \(MockNaming.handler(MockNaming.subscriptIdentifier(suffix: suffix)))",
            parameters: parameters,
            returnType: returnType,
            hasGenericReturn: hasGenericReturn,
            suffix: suffix,
            invokePrefix: invokePrefix,
            errorType: errorType
        )
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
\(MockNaming.instanceStorageName).withLock { storage in
    storage.\(MockNaming.callCount(MockNaming.subscriptIdentifier(suffix: suffix))) += 1
    storage.\(MockNaming.callArgs(MockNaming.subscriptIdentifier(suffix: suffix))).append(\(argsExpr))
}
""")))
        statements.append(recordCallStmt)
        let getHandlerStmt = CodeBlockItemSyntax(item: .decl(DeclSyntax(stringLiteral: "let _handler = \(MockNaming.instanceStorageName).withLock { $0.\(MockNaming.handler(MockNaming.subscriptIdentifier(suffix: suffix))) }")))
        statements.append(getHandlerStmt)

        statements.append(contentsOf: buildGuardedSubscriptHandlerReturn(
            guardBinding: "_handler",
            parameters: parameters,
            returnType: returnType,
            hasGenericReturn: hasGenericReturn,
            suffix: suffix,
            invokePrefix: invokePrefix,
            errorType: errorType
        ))
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
if let _handler = \(MockNaming.instanceStorageName).withLock({ $0.\(MockNaming.setHandler(MockNaming.subscriptIdentifier(suffix: suffix))) }) {
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
        effectfulGetAccessor(in: subscriptDecl.accessorBlock)
    }

    func buildSubscriptGetterClosureType(
        parameters: FunctionParameterListSyntax,
        returnType: TypeSyntax,
        genericParamNames: Set<String>,
        effects: AccessorEffectSpecifiersSyntax? = nil
    ) -> String {
        let erasedReturnType = Self.eraseGenericTypes(in: returnType, genericParamNames: genericParamNames)
        let returnTypeStr = erasedReturnType.description
        let effectsText = Self.effectsSuffix(for: effects)

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
