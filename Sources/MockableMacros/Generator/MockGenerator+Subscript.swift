import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Subscript Mock Generation

extension MockGenerator {
    /// Generates the members that mock a subscript requirement: the requirement's
    /// tracking slots (call count, captured indices, get handler, and a set handler
    /// for get-set subscripts) and the subscript witness. The identifier suffix
    /// encodes the index types so overloaded subscripts get distinct members.
    func generateSubscriptMock(
        _ subscriptDecl: SubscriptDeclSyntax,
        requirement: TrackingRequirement
    ) -> [MemberBlockItemSyntax] {
        var members = trackingMemberItems(for: requirement)

        let mockSubscript = generateSubscriptImplementation(
            subscriptDecl,
            isGetOnly: Self.isGetOnlySubscript(subscriptDecl),
            genericParamNames: Self.extractGenericParameterNames(from: subscriptDecl),
            identifier: requirement.identifier
        )
        members.append(MemberBlockItemSyntax(decl: mockSubscript))

        return members
    }

    /// A subscript requirement with no accessor block (`subscript(i: Int) -> Int`)
    /// is get-only, hence the `true` default.
    static func isGetOnlySubscript(_ subscriptDecl: SubscriptDeclSyntax) -> Bool {
        isGetOnly(subscriptDecl.accessorBlock, defaultWhenAbsent: true)
    }

    /// Builds the subscript witness, mirroring the requirement's parameter and return
    /// clauses. A get-only requirement uses the getter shorthand unless its getter is
    /// effectful, which needs an explicit `get async`/`get throws` accessor.
    private func generateSubscriptImplementation(
        _ subscriptDecl: SubscriptDeclSyntax,
        isGetOnly: Bool,
        genericParamNames: Set<String>,
        identifier: String
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
                identifier: identifier,
                handlerClosureType: buildSubscriptGetterClosureType(
                    parameters: parameters,
                    returnType: returnType,
                    genericParamNames: genericParamNames,
                    effects: getterEffects
                ),
                invokePrefix: invokePrefix,
                errorType: errorType
            )
        } else {
            getterStatements = buildDirectSubscriptGetterStatements(
                parameters: parameters,
                returnType: returnType,
                hasGenericReturn: hasGenericReturn,
                identifier: identifier,
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
                setterStatements.append(buildLockBasedSubscriptSetHandlerCallStatement(parameters: parameters, identifier: identifier))
            } else {
                setterStatements.append(buildDirectSubscriptSetHandlerCallStatement(parameters: parameters, identifier: identifier))
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

    /// The getter body for plain mocks: evaluate `@autoclosure` indices, record the
    /// call into the stored tracking properties, then invoke the handler.
    private func buildDirectSubscriptGetterStatements(
        parameters: FunctionParameterListSyntax,
        returnType: TypeSyntax,
        hasGenericReturn: Bool,
        identifier: String,
        invokePrefix: String = "",
        errorType: String? = nil
    ) -> [CodeBlockItemSyntax] {
        var getterStatements: [CodeBlockItemSyntax] = []
        getterStatements.append(contentsOf: Self.buildAutoclosureEvaluationStatements(parameters: parameters))

        getterStatements.append(contentsOf: Self.makeCallRecordingStatements(
            identifier: identifier,
            parameters: parameters
        ))

        getterStatements.append(contentsOf: buildSubscriptHandlerCallStatements(
            parameters: parameters,
            returnType: returnType,
            hasGenericReturn: hasGenericReturn,
            identifier: identifier,
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
        identifier: String,
        invokePrefix: String,
        errorType: String?
    ) -> [CodeBlockItemSyntax] {
        let returnTypeStr = Self.castTargetType(for: returnType)
        let guardStmt = Self.makeUnsetHandlerGuard(
            binding: guardBinding,
            elseBody: Self.unsetHandlerElseBody(
                returnType: returnType,
                handlerName: MockNaming.handler(identifier)
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

    /// The direct path's guard and handler invocation, binding `_handler` from the
    /// stored handler property.
    private func buildSubscriptHandlerCallStatements(
        parameters: FunctionParameterListSyntax,
        returnType: TypeSyntax,
        hasGenericReturn: Bool,
        identifier: String,
        invokePrefix: String = "",
        errorType: String? = nil
    ) -> [CodeBlockItemSyntax] {
        buildGuardedSubscriptHandlerReturn(
            guardBinding: "_handler = \(MockNaming.handler(identifier))",
            parameters: parameters,
            returnType: returnType,
            hasGenericReturn: hasGenericReturn,
            identifier: identifier,
            invokePrefix: invokePrefix,
            errorType: errorType
        )
    }

    /// The setter body for plain mocks. A setter has no return value, so an unset
    /// handler is a no-op rather than a `fatalError`; the handler receives the indices
    /// followed by `newValue`.
    private func buildDirectSubscriptSetHandlerCallStatement(
        parameters: FunctionParameterListSyntax,
        identifier: String
    ) -> CodeBlockItemSyntax {
        let handlerCallArgs: String
        if parameters.isEmpty {
            handlerCallArgs = "newValue"
        } else {
            handlerCallArgs = "\(buildHandlerCallArguments(parameters: parameters)), newValue"
        }

        return CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: """
if let _handler = \(MockNaming.setHandler(identifier)) {
    _handler(\(handlerCallArgs))
}
""")))
    }

    /// The getter body for `Sendable`/actor mocks: record the call and read the handler
    /// in a single `withLock`, then invoke the handler outside the lock.
    private func buildLockBasedSubscriptGetterStatements(
        parameters: FunctionParameterListSyntax,
        returnType: TypeSyntax,
        hasGenericReturn: Bool,
        identifier: String,
        handlerClosureType: String,
        invokePrefix: String = "",
        errorType: String? = nil
    ) -> [CodeBlockItemSyntax] {
        let argsExpr = Self.buildCallArgsExpression(parameters: parameters)

        var statements: [CodeBlockItemSyntax] = []
        // Evaluate @autoclosure arguments before taking the lock so user-supplied
        // expressions never run while the storage lock is held.
        statements.append(contentsOf: Self.buildAutoclosureEvaluationStatements(parameters: parameters))
        // Record the call and read the handler in a single lock acquisition,
        // mirroring the method witnesses.
        let withLockStmt = CodeBlockItemSyntax(item: .decl(DeclSyntax(stringLiteral: """
let _handler = \(MockNaming.instanceStorageName).withLock { storage -> (@Sendable \(handlerClosureType))? in
    storage.\(MockNaming.callCount(identifier)) += 1
    storage.\(MockNaming.callArgs(identifier)).append(\(argsExpr))
    return storage.\(MockNaming.handler(identifier))
}
""")))
        statements.append(withLockStmt)

        statements.append(contentsOf: buildGuardedSubscriptHandlerReturn(
            guardBinding: "_handler",
            parameters: parameters,
            returnType: returnType,
            hasGenericReturn: hasGenericReturn,
            identifier: identifier,
            invokePrefix: invokePrefix,
            errorType: errorType
        ))
        return statements
    }

    /// The setter body for `Sendable`/actor mocks: read the handler under the lock and
    /// invoke it outside. Setters record nothing, so there is no counter to update.
    private func buildLockBasedSubscriptSetHandlerCallStatement(
        parameters: FunctionParameterListSyntax,
        identifier: String
    ) -> CodeBlockItemSyntax {
        let handlerCallArgs: String
        if parameters.isEmpty {
            handlerCallArgs = "newValue"
        } else {
            handlerCallArgs = "\(buildHandlerCallArguments(parameters: parameters)), newValue"
        }

        return CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: """
if let _handler = \(MockNaming.instanceStorageName).withLock({ $0.\(MockNaming.setHandler(identifier)) }) {
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

    /// The get handler's closure type, e.g. `(Int) async throws -> String`. Like a
    /// method handler, it takes the indices as individual parameters.
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

    /// The set handler's closure type: the indices followed by the new value, e.g.
    /// `(Int, String) -> Void`. Setters are never effectful (SE-0310).
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
