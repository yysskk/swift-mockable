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

        let mockSubscript = generateSubscriptImplementation(subscriptDecl, requirement: requirement)
        members.append(MemberBlockItemSyntax(decl: mockSubscript))

        return members
    }

    /// Builds the subscript witness, mirroring the requirement's parameter and return
    /// clauses. A get-only requirement uses the getter shorthand unless its getter is
    /// effectful, which needs an explicit `get async`/`get throws` accessor.
    private func generateSubscriptImplementation(
        _ subscriptDecl: SubscriptDeclSyntax,
        requirement: TrackingRequirement
    ) -> SubscriptDeclSyntax {
        let identifier = requirement.identifier
        let isGetOnly = AccessorInspection.isGetOnlySubscript(subscriptDecl)
        let genericParamNames = TypeErasure.extractGenericParameterNames(from: subscriptDecl)
        let parameters = subscriptDecl.parameterClause.parameters
        let returnType = subscriptDecl.returnClause.type
        let hasGenericReturn = TypeErasure.typeContainsGeneric(returnType, genericParamNames: genericParamNames)
        let getterEffects = AccessorInspection.effectfulSubscriptGetter(subscriptDecl)?.effectSpecifiers
        let isAsync = getterEffects?.asyncSpecifier != nil
        let isThrows = getterEffects?.hasThrowsEffect ?? false
        let invokePrefix = "\(isThrows ? "try " : "")\(isAsync ? "await " : "")"
        let errorType = getterEffects?.throwsErrorType?.trimmedDescription
        // Subscripts are never type members, so their state is instance state.
        let access = trackingAccess(for: .instance)
        let names = WitnessNames(
            parameters: parameters,
            memberNames: access.referencedMembers([
                MockNaming.callCount(identifier),
                MockNaming.callArguments(identifier),
                MockNaming.handler(identifier),
                MockNaming.setHandler(identifier),
            ])
        )
        // The setter's implicit `newValue` is in scope alongside the indices, so an
        // index of that name would capture the value being assigned.
        let setterValueName = names.uniqueLocalName(startingAt: "newValue", parameters: parameters)

        let getterStatements = buildSubscriptGetterStatements(
            parameters: parameters,
            returnType: returnType,
            hasGenericReturn: hasGenericReturn,
            identifier: identifier,
            handlerType: requirement.handlerType ?? TrackingRequirement.fallbackHandlerType,
            invokePrefix: invokePrefix,
            errorType: errorType,
            access: access,
            names: names
        )

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
            var setterStatements = ParameterModel.buildParameterBindingStatements(parameters: parameters)
            setterStatements.append(buildSubscriptSetHandlerCallStatement(
                parameters: parameters,
                identifier: identifier,
                access: access,
                names: names,
                valueName: setterValueName
            ))

            accessors = AccessorBlockSyntax(
                accessors: .accessors(AccessorDeclListSyntax([
                    AccessorDeclSyntax(
                        accessorSpecifier: .keyword(.get),
                        body: CodeBlockSyntax(statements: CodeBlockItemListSyntax(getterStatements))
                    ),
                    AccessorDeclSyntax(
                        accessorSpecifier: .keyword(.set),
                        // An explicit accessor parameter is only spelled out when the
                        // implicit `newValue` would be shadowed by an index of that name.
                        parameters: setterValueName == "newValue"
                            ? nil
                            : AccessorParametersSyntax(name: .identifier(setterValueName)),
                        body: CodeBlockSyntax(statements: CodeBlockItemListSyntax(setterStatements))
                    )
                ]))
            )
        }

        return SubscriptDeclSyntax(
            modifiers: modifiers(for: .member),
            genericParameterClause: subscriptDecl.genericParameterClause,
            parameterClause: subscriptDecl.parameterClause,
            returnClause: subscriptDecl.returnClause,
            genericWhereClause: subscriptDecl.genericWhereClause,
            accessorBlock: accessors
        )
    }

    /// The getter body: evaluate `@autoclosure` indices, record the call and bind the
    /// handler the way `access` prescribes, then invoke the handler. On lock-backed
    /// access the call is recorded and the handler read in a single `withLock`,
    /// mirroring the method witnesses, and the handler is invoked outside the lock.
    private func buildSubscriptGetterStatements(
        parameters: FunctionParameterListSyntax,
        returnType: TypeSyntax,
        hasGenericReturn: Bool,
        identifier: String,
        handlerType: TypeSyntax,
        invokePrefix: String,
        errorType: String?,
        access: TrackingAccess,
        names: WitnessNames
    ) -> [CodeBlockItemSyntax] {
        var statements: [CodeBlockItemSyntax] = []
        // Evaluate @autoclosure arguments before the call is recorded, so a lock-backed
        // mock never runs a user-supplied expression while the storage lock is held.
        statements.append(contentsOf: ParameterModel.buildParameterBindingStatements(parameters: parameters))

        let binding = access.handlerBinding(
            identifier: identifier,
            recordedArguments: ParameterModel.buildCallArgumentsExpression(parameters: parameters),
            handlerType: handlerType,
            names: names
        )
        statements.append(contentsOf: binding.statements)

        statements.append(contentsOf: buildGuardedSubscriptHandlerReturn(
            guardBinding: binding.pattern,
            parameters: parameters,
            returnType: returnType,
            hasGenericReturn: hasGenericReturn,
            identifier: identifier,
            invokePrefix: invokePrefix,
            errorType: errorType,
            names: names
        ))
        return statements
    }

    /// Builds the unset-handler guard and the handler invocation of a subscript getter.
    /// `guardBinding` is the pattern that binds the handler, as `TrackingAccess`
    /// prescribes it.
    private func buildGuardedSubscriptHandlerReturn(
        guardBinding: String,
        parameters: FunctionParameterListSyntax,
        returnType: TypeSyntax,
        hasGenericReturn: Bool,
        identifier: String,
        invokePrefix: String,
        errorType: String?,
        names: WitnessNames
    ) -> [CodeBlockItemSyntax] {
        let returnTypeStr = TypeErasure.castTargetType(for: returnType)
        let guardStmt = Self.makeUnsetHandlerGuard(
            binding: guardBinding,
            elseBody: Self.unsetHandlerElseBody(
                returnType: returnType,
                handlerName: MockNaming.handler(identifier)
            )
        )
        let returnStmt = Self.makeHandlerReturnStatement(
            invokePrefix: invokePrefix,
            handlerName: names.handler,
            handlerCallArguments: buildHandlerCallArguments(parameters: parameters),
            castSuffix: hasGenericReturn ? " as! \(returnTypeStr)" : "",
            errorType: errorType
        )
        return [guardStmt, returnStmt]
    }

    /// The setter body. A setter has no return value, so an unset handler is a no-op
    /// rather than a `fatalError`; the handler receives the indices followed by
    /// `newValue`. Setters record nothing, so there is no counter to update: the
    /// handler is read the way `access` prescribes and invoked outside any lock.
    private func buildSubscriptSetHandlerCallStatement(
        parameters: FunctionParameterListSyntax,
        identifier: String,
        access: TrackingAccess,
        names: WitnessNames,
        valueName: String
    ) -> CodeBlockItemSyntax {
        let handlerCallArguments = setHandlerCallArguments(parameters: parameters, valueName: valueName)
        let pattern = access.handlerReadPattern(handlerName: MockNaming.setHandler(identifier), names: names)

        return CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: """
if let \(pattern) {
    \(names.handler)(\(handlerCallArguments))
}
""")))
    }

    /// The arguments a set handler receives: the indices followed by the new value.
    private func setHandlerCallArguments(
        parameters: FunctionParameterListSyntax,
        valueName: String
    ) -> String {
        if parameters.isEmpty {
            return valueName
        }
        return "\(buildHandlerCallArguments(parameters: parameters)), \(valueName)"
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
            return ParameterModel.buildSeparateParameterTypeList(parameters: parameters, genericParamNames: genericParamNames)
        }
        return ParameterModel.buildParameterTupleType(parameters: parameters, genericParamNames: genericParamNames).description
    }

    /// The get handler's closure type, e.g. `(Int) async throws -> String`. Like a
    /// method handler, it takes the indices as individual parameters.
    func buildSubscriptGetterClosureType(
        parameters: FunctionParameterListSyntax,
        returnType: TypeSyntax,
        genericParamNames: Set<String>,
        effects: AccessorEffectSpecifiersSyntax? = nil
    ) -> String {
        let erasedReturnType = TypeErasure.eraseGenericTypes(in: returnType, genericParamNames: genericParamNames)
        let returnTypeStr = erasedReturnType.description
        let effectsText = AccessorInspection.effectsSuffix(for: effects)

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
        let erasedReturnType = TypeErasure.eraseGenericTypes(in: returnType, genericParamNames: genericParamNames)
        let returnTypeStr = erasedReturnType.description

        if parameters.isEmpty {
            return "(\(returnTypeStr)) -> Void"
        }
        let paramList = subscriptHandlerParameterList(parameters: parameters, genericParamNames: genericParamNames)
        return "(\(paramList), \(returnTypeStr)) -> Void"
    }
}
