import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Subscript Mock Generation

extension MockGenerator {
    func generateSubscriptMock(_ subscriptDecl: SubscriptDeclSyntax) -> [MemberBlockItemSyntax] {
        var members: [MemberBlockItemSyntax] = []

        let parameters = subscriptDecl.parameterClause.parameters
        let returnType = subscriptDecl.returnClause.type
        let genericParamNames = Self.extractGenericParameterNames(from: subscriptDecl)
        let isGetOnly = Self.isGetOnlySubscript(subscriptDecl)

        if isSendable {
            // For Sendable protocols, generate computed properties that access the Mutex
            let callCountProperty = generateSendableSubscriptCallCountProperty()
            members.append(MemberBlockItemSyntax(decl: callCountProperty))

            let callArgsProperty = generateSendableSubscriptCallArgsProperty(
                parameters: parameters,
                genericParamNames: genericParamNames
            )
            members.append(MemberBlockItemSyntax(decl: callArgsProperty))

            let handlerProperty = generateSendableSubscriptHandlerProperty(
                parameters: parameters,
                returnType: returnType,
                isGetOnly: isGetOnly,
                genericParamNames: genericParamNames
            )
            members.append(MemberBlockItemSyntax(decl: handlerProperty))

            if !isGetOnly {
                let setHandlerProperty = generateSendableSubscriptSetHandlerProperty(
                    parameters: parameters,
                    returnType: returnType,
                    genericParamNames: genericParamNames
                )
                members.append(MemberBlockItemSyntax(decl: setHandlerProperty))
            }

            let mockSubscript = generateSendableMockSubscript(
                subscriptDecl,
                isGetOnly: isGetOnly,
                genericParamNames: genericParamNames
            )
            members.append(MemberBlockItemSyntax(decl: mockSubscript))
        } else {
            // Generate call count property
            let callCountProperty = generateSubscriptCallCountProperty()
            members.append(MemberBlockItemSyntax(decl: callCountProperty))

            // Generate call arguments storage
            let callArgsProperty = generateSubscriptCallArgsProperty(
                parameters: parameters,
                genericParamNames: genericParamNames
            )
            members.append(MemberBlockItemSyntax(decl: callArgsProperty))

            // Generate handler property (for getter)
            let handlerProperty = generateSubscriptHandlerProperty(
                parameters: parameters,
                returnType: returnType,
                isGetOnly: isGetOnly,
                genericParamNames: genericParamNames
            )
            members.append(MemberBlockItemSyntax(decl: handlerProperty))

            // Generate set handler property (for setter) if not get-only
            if !isGetOnly {
                let setHandlerProperty = generateSubscriptSetHandlerProperty(
                    parameters: parameters,
                    returnType: returnType,
                    genericParamNames: genericParamNames
                )
                members.append(MemberBlockItemSyntax(decl: setHandlerProperty))
            }

            // Generate the mock subscript implementation
            let mockSubscript = generateMockSubscript(
                subscriptDecl,
                isGetOnly: isGetOnly,
                genericParamNames: genericParamNames
            )
            members.append(MemberBlockItemSyntax(decl: mockSubscript))
        }

        return members
    }

    func generateActorSubscriptMock(_ subscriptDecl: SubscriptDeclSyntax) -> [MemberBlockItemSyntax] {
        var members: [MemberBlockItemSyntax] = []

        let parameters = subscriptDecl.parameterClause.parameters
        let returnType = subscriptDecl.returnClause.type
        let genericParamNames = Self.extractGenericParameterNames(from: subscriptDecl)
        let isGetOnly = Self.isGetOnlySubscript(subscriptDecl)

        // Use Mutex-based pattern with nonisolated computed properties for actor
        let callCountProperty = generateActorSubscriptCallCountProperty()
        members.append(MemberBlockItemSyntax(decl: callCountProperty))

        let callArgsProperty = generateActorSubscriptCallArgsProperty(
            parameters: parameters,
            genericParamNames: genericParamNames
        )
        members.append(MemberBlockItemSyntax(decl: callArgsProperty))

        let handlerProperty = generateActorSubscriptHandlerProperty(
            parameters: parameters,
            returnType: returnType,
            isGetOnly: isGetOnly,
            genericParamNames: genericParamNames
        )
        members.append(MemberBlockItemSyntax(decl: handlerProperty))

        if !isGetOnly {
            let setHandlerProperty = generateActorSubscriptSetHandlerProperty(
                parameters: parameters,
                returnType: returnType,
                genericParamNames: genericParamNames
            )
            members.append(MemberBlockItemSyntax(decl: setHandlerProperty))
        }

        let mockSubscript = generateActorMockSubscript(
            subscriptDecl,
            isGetOnly: isGetOnly,
            genericParamNames: genericParamNames
        )
        members.append(MemberBlockItemSyntax(decl: mockSubscript))

        return members
    }

    // MARK: - Helper to check if subscript is get-only

    static func isGetOnlySubscript(_ subscriptDecl: SubscriptDeclSyntax) -> Bool {
        guard let accessorBlock = subscriptDecl.accessorBlock else {
            return true // No accessor block means get-only
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

    // MARK: - Helper to extract generic parameter names from subscript

    static func extractGenericParameterNames(from subscriptDecl: SubscriptDeclSyntax) -> Set<String> {
        guard let genericClause = subscriptDecl.genericParameterClause else {
            return []
        }
        return Set(genericClause.parameters.map { $0.name.text })
    }

    // MARK: - Regular Mock Properties

    private func generateSubscriptCallCountProperty() -> VariableDeclSyntax {
        VariableDeclSyntax(
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.public))
            ]),
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier("subscriptCallCount")),
                    typeAnnotation: TypeAnnotationSyntax(type: TypeSyntax(stringLiteral: "Int")),
                    initializer: InitializerClauseSyntax(value: IntegerLiteralExprSyntax(literal: .integerLiteral("0")))
                )
            ])
        )
    }

    private func generateSubscriptCallArgsProperty(
        parameters: FunctionParameterListSyntax,
        genericParamNames: Set<String>
    ) -> VariableDeclSyntax {
        let tupleType = Self.buildParameterTupleType(parameters: parameters, genericParamNames: genericParamNames)

        return VariableDeclSyntax(
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.public))
            ]),
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier("subscriptCallArgs")),
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

    private func generateSubscriptHandlerProperty(
        parameters: FunctionParameterListSyntax,
        returnType: TypeSyntax,
        isGetOnly: Bool,
        genericParamNames: Set<String>
    ) -> VariableDeclSyntax {
        let paramTupleType = Self.buildParameterTupleType(
            parameters: parameters,
            genericParamNames: genericParamNames
        )
        let erasedReturnType = Self.eraseGenericTypes(in: returnType, genericParamNames: genericParamNames)
        let returnTypeStr = erasedReturnType.description

        let closureType = parameters.isEmpty ? "() -> \(returnTypeStr)" : "(\(paramTupleType.description)) -> \(returnTypeStr)"

        return VariableDeclSyntax(
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.public))
            ]),
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier("subscriptHandler")),
                    typeAnnotation: TypeAnnotationSyntax(
                        type: OptionalTypeSyntax(wrappedType: TypeSyntax(stringLiteral: "(@Sendable \(closureType))"))
                    ),
                    initializer: InitializerClauseSyntax(value: NilLiteralExprSyntax())
                )
            ])
        )
    }

    private func generateSubscriptSetHandlerProperty(
        parameters: FunctionParameterListSyntax,
        returnType: TypeSyntax,
        genericParamNames: Set<String>
    ) -> VariableDeclSyntax {
        let paramTupleType = Self.buildParameterTupleType(
            parameters: parameters,
            genericParamNames: genericParamNames
        )
        let erasedReturnType = Self.eraseGenericTypes(in: returnType, genericParamNames: genericParamNames)
        let returnTypeStr = erasedReturnType.description

        // Set handler takes (index, newValue) -> Void
        let closureType: String
        if parameters.isEmpty {
            closureType = "(\(returnTypeStr)) -> Void"
        } else {
            closureType = "(\(paramTupleType.description), \(returnTypeStr)) -> Void"
        }

        return VariableDeclSyntax(
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.public))
            ]),
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier("subscriptSetHandler")),
                    typeAnnotation: TypeAnnotationSyntax(
                        type: OptionalTypeSyntax(wrappedType: TypeSyntax(stringLiteral: "(@Sendable \(closureType))"))
                    ),
                    initializer: InitializerClauseSyntax(value: NilLiteralExprSyntax())
                )
            ])
        )
    }

    private func generateMockSubscript(
        _ subscriptDecl: SubscriptDeclSyntax,
        isGetOnly: Bool,
        genericParamNames: Set<String>
    ) -> SubscriptDeclSyntax {
        let parameters = subscriptDecl.parameterClause.parameters
        let returnType = subscriptDecl.returnClause.type
        let hasGenericReturn = Self.typeContainsGeneric(returnType, genericParamNames: genericParamNames)

        // Build getter body
        var getterStatements: [CodeBlockItemSyntax] = []

        // Increment call count
        let incrementStmt = InfixOperatorExprSyntax(
            leftOperand: DeclReferenceExprSyntax(baseName: .identifier("subscriptCallCount")),
            operator: BinaryOperatorExprSyntax(operator: .binaryOperator("+=")),
            rightOperand: IntegerLiteralExprSyntax(literal: .integerLiteral("1"))
        )
        getterStatements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(incrementStmt))))

        // Record call arguments
        let argsExpr = Self.buildSubscriptArgsExpression(parameters: parameters)
        let appendExpr = FunctionCallExprSyntax(
            calledExpression: MemberAccessExprSyntax(
                base: DeclReferenceExprSyntax(baseName: .identifier("subscriptCallArgs")),
                name: .identifier("append")
            ),
            leftParen: .leftParenToken(),
            arguments: LabeledExprListSyntax([
                LabeledExprSyntax(expression: argsExpr)
            ]),
            rightParen: .rightParenToken()
        )
        getterStatements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(appendExpr))))

        // Call handler
        let handlerCallStmts = buildSubscriptHandlerCallStatements(
            parameters: parameters,
            returnType: returnType,
            hasGenericReturn: hasGenericReturn
        )
        getterStatements.append(contentsOf: handlerCallStmts)

        let getterBody = CodeBlockSyntax(
            statements: CodeBlockItemListSyntax(getterStatements)
        )

        let accessors: AccessorBlockSyntax
        if isGetOnly {
            accessors = AccessorBlockSyntax(
                accessors: .getter(CodeBlockItemListSyntax(getterStatements))
            )
        } else {
            // Build setter body
            var setterStatements: [CodeBlockItemSyntax] = []
            let setterHandlerCall = buildSubscriptSetHandlerCallStatement(parameters: parameters)
            setterStatements.append(setterHandlerCall)

            let setterBody = CodeBlockSyntax(
                statements: CodeBlockItemListSyntax(setterStatements)
            )

            accessors = AccessorBlockSyntax(
                accessors: .accessors(AccessorDeclListSyntax([
                    AccessorDeclSyntax(
                        accessorSpecifier: .keyword(.get),
                        body: getterBody
                    ),
                    AccessorDeclSyntax(
                        accessorSpecifier: .keyword(.set),
                        body: setterBody
                    )
                ]))
            )
        }

        return SubscriptDeclSyntax(
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.public))
            ]),
            genericParameterClause: subscriptDecl.genericParameterClause,
            parameterClause: subscriptDecl.parameterClause,
            returnClause: subscriptDecl.returnClause,
            genericWhereClause: subscriptDecl.genericWhereClause,
            accessorBlock: accessors
        )
    }

    private func buildSubscriptHandlerCallStatements(
        parameters: FunctionParameterListSyntax,
        returnType: TypeSyntax,
        hasGenericReturn: Bool
    ) -> [CodeBlockItemSyntax] {
        let argsExpr = Self.buildSubscriptArgsExpression(parameters: parameters)
        let handlerCallArgs = parameters.isEmpty ? "" : "\(argsExpr)"

        let returnTypeStr = returnType.description
        let castSuffix = hasGenericReturn ? " as! \(returnTypeStr)" : ""
        let guardStmt = CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: """
guard let _handler = subscriptHandler else {
    fatalError("\\(Self.self).subscriptHandler is not set")
}
""")))
        let returnStmt = CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: "return _handler(\(handlerCallArgs))\(castSuffix)")))
        return [guardStmt, returnStmt]
    }

    private func buildSubscriptSetHandlerCallStatement(parameters: FunctionParameterListSyntax) -> CodeBlockItemSyntax {
        let argsExpr = Self.buildSubscriptArgsExpression(parameters: parameters)
        let handlerCallArgs: String
        if parameters.isEmpty {
            handlerCallArgs = "newValue"
        } else {
            handlerCallArgs = "\(argsExpr), newValue"
        }

        return CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: """
if let _handler = subscriptSetHandler {
    _handler(\(handlerCallArgs))
}
""")))
    }

    // MARK: - Sendable Mock Properties

    private func generateSendableSubscriptCallCountProperty() -> VariableDeclSyntax {
        VariableDeclSyntax(
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.public))
            ]),
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier("subscriptCallCount")),
                    typeAnnotation: TypeAnnotationSyntax(type: TypeSyntax(stringLiteral: "Int")),
                    accessorBlock: AccessorBlockSyntax(
                        accessors: .accessors(AccessorDeclListSyntax([
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.get),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.subscriptCallCount }")))
                                    ])
                                )
                            ),
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.set),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.subscriptCallCount = newValue }")))
                                    ])
                                )
                            )
                        ]))
                    )
                )
            ])
        )
    }

    private func generateSendableSubscriptCallArgsProperty(
        parameters: FunctionParameterListSyntax,
        genericParamNames: Set<String>
    ) -> VariableDeclSyntax {
        let tupleType = Self.buildParameterTupleType(parameters: parameters, genericParamNames: genericParamNames)

        return VariableDeclSyntax(
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.public))
            ]),
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier("subscriptCallArgs")),
                    typeAnnotation: TypeAnnotationSyntax(type: ArrayTypeSyntax(element: tupleType)),
                    accessorBlock: AccessorBlockSyntax(
                        accessors: .accessors(AccessorDeclListSyntax([
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.get),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.subscriptCallArgs }")))
                                    ])
                                )
                            ),
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.set),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.subscriptCallArgs = newValue }")))
                                    ])
                                )
                            )
                        ]))
                    )
                )
            ])
        )
    }

    private func generateSendableSubscriptHandlerProperty(
        parameters: FunctionParameterListSyntax,
        returnType: TypeSyntax,
        isGetOnly: Bool,
        genericParamNames: Set<String>
    ) -> VariableDeclSyntax {
        let paramTupleType = Self.buildParameterTupleType(
            parameters: parameters,
            genericParamNames: genericParamNames
        )
        let erasedReturnType = Self.eraseGenericTypes(in: returnType, genericParamNames: genericParamNames)
        let returnTypeStr = erasedReturnType.description

        let closureType = parameters.isEmpty ? "() -> \(returnTypeStr)" : "(\(paramTupleType.description)) -> \(returnTypeStr)"
        let handlerType = "(@Sendable \(closureType))?"

        return VariableDeclSyntax(
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.public))
            ]),
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier("subscriptHandler")),
                    typeAnnotation: TypeAnnotationSyntax(type: TypeSyntax(stringLiteral: handlerType)),
                    accessorBlock: AccessorBlockSyntax(
                        accessors: .accessors(AccessorDeclListSyntax([
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.get),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.subscriptHandler }")))
                                    ])
                                )
                            ),
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.set),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.subscriptHandler = newValue }")))
                                    ])
                                )
                            )
                        ]))
                    )
                )
            ])
        )
    }

    private func generateSendableSubscriptSetHandlerProperty(
        parameters: FunctionParameterListSyntax,
        returnType: TypeSyntax,
        genericParamNames: Set<String>
    ) -> VariableDeclSyntax {
        let paramTupleType = Self.buildParameterTupleType(
            parameters: parameters,
            genericParamNames: genericParamNames
        )
        let erasedReturnType = Self.eraseGenericTypes(in: returnType, genericParamNames: genericParamNames)
        let returnTypeStr = erasedReturnType.description

        let closureType: String
        if parameters.isEmpty {
            closureType = "(\(returnTypeStr)) -> Void"
        } else {
            closureType = "(\(paramTupleType.description), \(returnTypeStr)) -> Void"
        }
        let handlerType = "(@Sendable \(closureType))?"

        return VariableDeclSyntax(
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.public))
            ]),
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier("subscriptSetHandler")),
                    typeAnnotation: TypeAnnotationSyntax(type: TypeSyntax(stringLiteral: handlerType)),
                    accessorBlock: AccessorBlockSyntax(
                        accessors: .accessors(AccessorDeclListSyntax([
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.get),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.subscriptSetHandler }")))
                                    ])
                                )
                            ),
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.set),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.subscriptSetHandler = newValue }")))
                                    ])
                                )
                            )
                        ]))
                    )
                )
            ])
        )
    }

    private func generateSendableMockSubscript(
        _ subscriptDecl: SubscriptDeclSyntax,
        isGetOnly: Bool,
        genericParamNames: Set<String>
    ) -> SubscriptDeclSyntax {
        let parameters = subscriptDecl.parameterClause.parameters
        let returnType = subscriptDecl.returnClause.type
        let hasGenericReturn = Self.typeContainsGeneric(returnType, genericParamNames: genericParamNames)

        // Build getter body with Mutex access
        var getterStatements: [CodeBlockItemSyntax] = []

        // Increment call count and record args using withLock
        let argsExpr = Self.buildSubscriptArgsExpression(parameters: parameters)
        let recordCallStmt = CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: """
_storage.withLock { storage in
    storage.subscriptCallCount += 1
    storage.subscriptCallArgs.append(\(argsExpr))
}
""")))
        getterStatements.append(recordCallStmt)

        // Call handler
        let handlerCallStmts = buildSendableSubscriptHandlerCallStatements(
            parameters: parameters,
            returnType: returnType,
            hasGenericReturn: hasGenericReturn
        )
        getterStatements.append(contentsOf: handlerCallStmts)

        let getterBody = CodeBlockSyntax(
            statements: CodeBlockItemListSyntax(getterStatements)
        )

        let accessors: AccessorBlockSyntax
        if isGetOnly {
            accessors = AccessorBlockSyntax(
                accessors: .getter(CodeBlockItemListSyntax(getterStatements))
            )
        } else {
            // Build setter body
            var setterStatements: [CodeBlockItemSyntax] = []
            let setterHandlerCall = buildSendableSubscriptSetHandlerCallStatement(parameters: parameters)
            setterStatements.append(setterHandlerCall)

            let setterBody = CodeBlockSyntax(
                statements: CodeBlockItemListSyntax(setterStatements)
            )

            accessors = AccessorBlockSyntax(
                accessors: .accessors(AccessorDeclListSyntax([
                    AccessorDeclSyntax(
                        accessorSpecifier: .keyword(.get),
                        body: getterBody
                    ),
                    AccessorDeclSyntax(
                        accessorSpecifier: .keyword(.set),
                        body: setterBody
                    )
                ]))
            )
        }

        return SubscriptDeclSyntax(
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.public))
            ]),
            genericParameterClause: subscriptDecl.genericParameterClause,
            parameterClause: subscriptDecl.parameterClause,
            returnClause: subscriptDecl.returnClause,
            genericWhereClause: subscriptDecl.genericWhereClause,
            accessorBlock: accessors
        )
    }

    private func buildSendableSubscriptHandlerCallStatements(
        parameters: FunctionParameterListSyntax,
        returnType: TypeSyntax,
        hasGenericReturn: Bool
    ) -> [CodeBlockItemSyntax] {
        let argsExpr = Self.buildSubscriptArgsExpression(parameters: parameters)
        let handlerCallArgs = parameters.isEmpty ? "" : "\(argsExpr)"

        let returnTypeStr = returnType.description
        let castSuffix = hasGenericReturn ? " as! \(returnTypeStr)" : ""
        let guardStmt = CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: """
guard let _handler = _storage.withLock({ $0.subscriptHandler }) else {
    fatalError("\\(Self.self).subscriptHandler is not set")
}
""")))
        let returnStmt = CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: "return _handler(\(handlerCallArgs))\(castSuffix)")))
        return [guardStmt, returnStmt]
    }

    private func buildSendableSubscriptSetHandlerCallStatement(parameters: FunctionParameterListSyntax) -> CodeBlockItemSyntax {
        let argsExpr = Self.buildSubscriptArgsExpression(parameters: parameters)
        let handlerCallArgs: String
        if parameters.isEmpty {
            handlerCallArgs = "newValue"
        } else {
            handlerCallArgs = "\(argsExpr), newValue"
        }

        return CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: """
if let _handler = _storage.withLock({ $0.subscriptSetHandler }) {
    _handler(\(handlerCallArgs))
}
""")))
    }

    // MARK: - Actor Mock Properties

    private func generateActorSubscriptCallCountProperty() -> VariableDeclSyntax {
        VariableDeclSyntax(
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.public)),
                DeclModifierSyntax(name: .keyword(.nonisolated))
            ]),
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier("subscriptCallCount")),
                    typeAnnotation: TypeAnnotationSyntax(type: TypeSyntax(stringLiteral: "Int")),
                    accessorBlock: AccessorBlockSyntax(
                        accessors: .accessors(AccessorDeclListSyntax([
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.get),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.subscriptCallCount }")))
                                    ])
                                )
                            ),
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.set),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.subscriptCallCount = newValue }")))
                                    ])
                                )
                            )
                        ]))
                    )
                )
            ])
        )
    }

    private func generateActorSubscriptCallArgsProperty(
        parameters: FunctionParameterListSyntax,
        genericParamNames: Set<String>
    ) -> VariableDeclSyntax {
        let tupleType = Self.buildParameterTupleType(parameters: parameters, genericParamNames: genericParamNames)

        return VariableDeclSyntax(
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.public)),
                DeclModifierSyntax(name: .keyword(.nonisolated))
            ]),
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier("subscriptCallArgs")),
                    typeAnnotation: TypeAnnotationSyntax(type: ArrayTypeSyntax(element: tupleType)),
                    accessorBlock: AccessorBlockSyntax(
                        accessors: .accessors(AccessorDeclListSyntax([
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.get),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.subscriptCallArgs }")))
                                    ])
                                )
                            ),
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.set),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.subscriptCallArgs = newValue }")))
                                    ])
                                )
                            )
                        ]))
                    )
                )
            ])
        )
    }

    private func generateActorSubscriptHandlerProperty(
        parameters: FunctionParameterListSyntax,
        returnType: TypeSyntax,
        isGetOnly: Bool,
        genericParamNames: Set<String>
    ) -> VariableDeclSyntax {
        let paramTupleType = Self.buildParameterTupleType(
            parameters: parameters,
            genericParamNames: genericParamNames
        )
        let erasedReturnType = Self.eraseGenericTypes(in: returnType, genericParamNames: genericParamNames)
        let returnTypeStr = erasedReturnType.description

        let closureType = parameters.isEmpty ? "() -> \(returnTypeStr)" : "(\(paramTupleType.description)) -> \(returnTypeStr)"
        let handlerType = "(@Sendable \(closureType))?"

        return VariableDeclSyntax(
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.public)),
                DeclModifierSyntax(name: .keyword(.nonisolated))
            ]),
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier("subscriptHandler")),
                    typeAnnotation: TypeAnnotationSyntax(type: TypeSyntax(stringLiteral: handlerType)),
                    accessorBlock: AccessorBlockSyntax(
                        accessors: .accessors(AccessorDeclListSyntax([
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.get),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.subscriptHandler }")))
                                    ])
                                )
                            ),
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.set),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.subscriptHandler = newValue }")))
                                    ])
                                )
                            )
                        ]))
                    )
                )
            ])
        )
    }

    private func generateActorSubscriptSetHandlerProperty(
        parameters: FunctionParameterListSyntax,
        returnType: TypeSyntax,
        genericParamNames: Set<String>
    ) -> VariableDeclSyntax {
        let paramTupleType = Self.buildParameterTupleType(
            parameters: parameters,
            genericParamNames: genericParamNames
        )
        let erasedReturnType = Self.eraseGenericTypes(in: returnType, genericParamNames: genericParamNames)
        let returnTypeStr = erasedReturnType.description

        let closureType: String
        if parameters.isEmpty {
            closureType = "(\(returnTypeStr)) -> Void"
        } else {
            closureType = "(\(paramTupleType.description), \(returnTypeStr)) -> Void"
        }
        let handlerType = "(@Sendable \(closureType))?"

        return VariableDeclSyntax(
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.public)),
                DeclModifierSyntax(name: .keyword(.nonisolated))
            ]),
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier("subscriptSetHandler")),
                    typeAnnotation: TypeAnnotationSyntax(type: TypeSyntax(stringLiteral: handlerType)),
                    accessorBlock: AccessorBlockSyntax(
                        accessors: .accessors(AccessorDeclListSyntax([
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.get),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.subscriptSetHandler }")))
                                    ])
                                )
                            ),
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.set),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.subscriptSetHandler = newValue }")))
                                    ])
                                )
                            )
                        ]))
                    )
                )
            ])
        )
    }

    private func generateActorMockSubscript(
        _ subscriptDecl: SubscriptDeclSyntax,
        isGetOnly: Bool,
        genericParamNames: Set<String>
    ) -> SubscriptDeclSyntax {
        // Actor subscripts use the same Sendable pattern
        return generateSendableMockSubscript(subscriptDecl, isGetOnly: isGetOnly, genericParamNames: genericParamNames)
    }

    // MARK: - Helper to build args expression for subscripts

    static func buildSubscriptArgsExpression(parameters: FunctionParameterListSyntax) -> ExprSyntax {
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
