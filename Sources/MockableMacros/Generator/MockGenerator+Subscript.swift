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
        let suffix = Self.subscriptIdentifierSuffix(from: subscriptDecl)

        if isSendable {
            // For Sendable protocols, generate computed properties that access the Mutex
            let callCountProperty = generateSendableSubscriptCallCountProperty(suffix: suffix)
            members.append(MemberBlockItemSyntax(decl: callCountProperty))

            let callArgsProperty = generateSendableSubscriptCallArgsProperty(
                parameters: parameters,
                genericParamNames: genericParamNames,
                suffix: suffix
            )
            members.append(MemberBlockItemSyntax(decl: callArgsProperty))

            let handlerProperty = generateSendableSubscriptHandlerProperty(
                parameters: parameters,
                returnType: returnType,
                genericParamNames: genericParamNames,
                suffix: suffix
            )
            members.append(MemberBlockItemSyntax(decl: handlerProperty))

            if !isGetOnly {
                let setHandlerProperty = generateSendableSubscriptSetHandlerProperty(
                    parameters: parameters,
                    returnType: returnType,
                    genericParamNames: genericParamNames,
                    suffix: suffix
                )
                members.append(MemberBlockItemSyntax(decl: setHandlerProperty))
            }

            let mockSubscript = generateSendableMockSubscript(
                subscriptDecl,
                isGetOnly: isGetOnly,
                genericParamNames: genericParamNames,
                suffix: suffix
            )
            members.append(MemberBlockItemSyntax(decl: mockSubscript))
        } else {
            // Generate call count property
            let callCountProperty = generateSubscriptCallCountProperty(suffix: suffix)
            members.append(MemberBlockItemSyntax(decl: callCountProperty))

            // Generate call arguments storage
            let callArgsProperty = generateSubscriptCallArgsProperty(
                parameters: parameters,
                genericParamNames: genericParamNames,
                suffix: suffix
            )
            members.append(MemberBlockItemSyntax(decl: callArgsProperty))

            // Generate handler property (for getter)
            let handlerProperty = generateSubscriptHandlerProperty(
                parameters: parameters,
                returnType: returnType,
                genericParamNames: genericParamNames,
                suffix: suffix
            )
            members.append(MemberBlockItemSyntax(decl: handlerProperty))

            // Generate set handler property (for setter) if not get-only
            if !isGetOnly {
                let setHandlerProperty = generateSubscriptSetHandlerProperty(
                    parameters: parameters,
                    returnType: returnType,
                    genericParamNames: genericParamNames,
                    suffix: suffix
                )
                members.append(MemberBlockItemSyntax(decl: setHandlerProperty))
            }

            // Generate the mock subscript implementation
            let mockSubscript = generateMockSubscript(
                subscriptDecl,
                isGetOnly: isGetOnly,
                genericParamNames: genericParamNames,
                suffix: suffix
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
        let suffix = Self.subscriptIdentifierSuffix(from: subscriptDecl)

        // Use Mutex-based pattern with nonisolated computed properties for actor
        let callCountProperty = generateActorSubscriptCallCountProperty(suffix: suffix)
        members.append(MemberBlockItemSyntax(decl: callCountProperty))

        let callArgsProperty = generateActorSubscriptCallArgsProperty(
            parameters: parameters,
            genericParamNames: genericParamNames,
            suffix: suffix
        )
        members.append(MemberBlockItemSyntax(decl: callArgsProperty))

        let handlerProperty = generateActorSubscriptHandlerProperty(
            parameters: parameters,
            returnType: returnType,
            genericParamNames: genericParamNames,
            suffix: suffix
        )
        members.append(MemberBlockItemSyntax(decl: handlerProperty))

        if !isGetOnly {
            let setHandlerProperty = generateActorSubscriptSetHandlerProperty(
                parameters: parameters,
                returnType: returnType,
                genericParamNames: genericParamNames,
                suffix: suffix
            )
            members.append(MemberBlockItemSyntax(decl: setHandlerProperty))
        }

        let mockSubscript = generateActorMockSubscript(
            subscriptDecl,
            isGetOnly: isGetOnly,
            genericParamNames: genericParamNames,
            suffix: suffix
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

    // MARK: - Helper to generate unique subscript identifier suffix

    /// Generates a unique suffix based on parameter types to distinguish overloaded subscripts.
    /// Example: `subscript(index: Int)` -> "Int", `subscript(row: Int, column: Int)` -> "IntInt"
    static func subscriptIdentifierSuffix(from subscriptDecl: SubscriptDeclSyntax) -> String {
        let parameters = subscriptDecl.parameterClause.parameters
        if parameters.isEmpty {
            return ""
        }

        let typeNames = parameters.map { param -> String in
            // Get the base type name, stripping generics and optionals for simplicity
            let typeName = param.type.trimmedDescription
            return sanitizeTypeName(typeName)
        }

        return typeNames.joined()
    }

    /// Sanitizes a type name for use in an identifier.
    /// Handles special characters, generics, optionals, and arrays.
    private static func sanitizeTypeName(_ typeName: String) -> String {
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

    // MARK: - Regular Mock Properties

    private func generateSubscriptCallCountProperty(suffix: String) -> VariableDeclSyntax {
        VariableDeclSyntax(
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.public))
            ]),
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier("subscript\(suffix)CallCount")),
                    typeAnnotation: TypeAnnotationSyntax(type: TypeSyntax(stringLiteral: "Int")),
                    initializer: InitializerClauseSyntax(value: IntegerLiteralExprSyntax(literal: .integerLiteral("0")))
                )
            ])
        )
    }

    private func generateSubscriptCallArgsProperty(
        parameters: FunctionParameterListSyntax,
        genericParamNames: Set<String>,
        suffix: String
    ) -> VariableDeclSyntax {
        let tupleType = Self.buildParameterTupleType(parameters: parameters, genericParamNames: genericParamNames)

        return VariableDeclSyntax(
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.public))
            ]),
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier("subscript\(suffix)CallArgs")),
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
        genericParamNames: Set<String>,
        suffix: String
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
                    pattern: IdentifierPatternSyntax(identifier: .identifier("subscript\(suffix)Handler")),
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
        genericParamNames: Set<String>,
        suffix: String
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
                    pattern: IdentifierPatternSyntax(identifier: .identifier("subscript\(suffix)SetHandler")),
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
        genericParamNames: Set<String>,
        suffix: String
    ) -> SubscriptDeclSyntax {
        let parameters = subscriptDecl.parameterClause.parameters
        let returnType = subscriptDecl.returnClause.type
        let hasGenericReturn = Self.typeContainsGeneric(returnType, genericParamNames: genericParamNames)

        // Build getter body
        var getterStatements: [CodeBlockItemSyntax] = []

        // Increment call count
        let incrementStmt = InfixOperatorExprSyntax(
            leftOperand: DeclReferenceExprSyntax(baseName: .identifier("subscript\(suffix)CallCount")),
            operator: BinaryOperatorExprSyntax(operator: .binaryOperator("+=")),
            rightOperand: IntegerLiteralExprSyntax(literal: .integerLiteral("1"))
        )
        getterStatements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(incrementStmt))))

        // Record call arguments
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

        // Call handler
        let handlerCallStmts = buildSubscriptHandlerCallStatements(
            parameters: parameters,
            returnType: returnType,
            hasGenericReturn: hasGenericReturn,
            suffix: suffix
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
            let setterHandlerCall = buildSubscriptSetHandlerCallStatement(parameters: parameters, suffix: suffix)
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

    private func buildSubscriptSetHandlerCallStatement(parameters: FunctionParameterListSyntax, suffix: String) -> CodeBlockItemSyntax {
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

    // MARK: - Sendable Mock Properties

    private func generateSendableSubscriptCallCountProperty(suffix: String) -> VariableDeclSyntax {
        VariableDeclSyntax(
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.public))
            ]),
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier("subscript\(suffix)CallCount")),
                    typeAnnotation: TypeAnnotationSyntax(type: TypeSyntax(stringLiteral: "Int")),
                    accessorBlock: AccessorBlockSyntax(
                        accessors: .accessors(AccessorDeclListSyntax([
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.get),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.subscript\(suffix)CallCount }")))
                                    ])
                                )
                            ),
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.set),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.subscript\(suffix)CallCount = newValue }")))
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
        genericParamNames: Set<String>,
        suffix: String
    ) -> VariableDeclSyntax {
        let tupleType = Self.buildParameterTupleType(parameters: parameters, genericParamNames: genericParamNames)

        return VariableDeclSyntax(
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.public))
            ]),
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier("subscript\(suffix)CallArgs")),
                    typeAnnotation: TypeAnnotationSyntax(type: ArrayTypeSyntax(element: tupleType)),
                    accessorBlock: AccessorBlockSyntax(
                        accessors: .accessors(AccessorDeclListSyntax([
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.get),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.subscript\(suffix)CallArgs }")))
                                    ])
                                )
                            ),
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.set),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.subscript\(suffix)CallArgs = newValue }")))
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
        genericParamNames: Set<String>,
        suffix: String
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
                    pattern: IdentifierPatternSyntax(identifier: .identifier("subscript\(suffix)Handler")),
                    typeAnnotation: TypeAnnotationSyntax(type: TypeSyntax(stringLiteral: handlerType)),
                    accessorBlock: AccessorBlockSyntax(
                        accessors: .accessors(AccessorDeclListSyntax([
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.get),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.subscript\(suffix)Handler }")))
                                    ])
                                )
                            ),
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.set),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.subscript\(suffix)Handler = newValue }")))
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
        genericParamNames: Set<String>,
        suffix: String
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
                    pattern: IdentifierPatternSyntax(identifier: .identifier("subscript\(suffix)SetHandler")),
                    typeAnnotation: TypeAnnotationSyntax(type: TypeSyntax(stringLiteral: handlerType)),
                    accessorBlock: AccessorBlockSyntax(
                        accessors: .accessors(AccessorDeclListSyntax([
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.get),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.subscript\(suffix)SetHandler }")))
                                    ])
                                )
                            ),
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.set),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.subscript\(suffix)SetHandler = newValue }")))
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
        genericParamNames: Set<String>,
        suffix: String
    ) -> SubscriptDeclSyntax {
        let parameters = subscriptDecl.parameterClause.parameters
        let returnType = subscriptDecl.returnClause.type
        let hasGenericReturn = Self.typeContainsGeneric(returnType, genericParamNames: genericParamNames)

        // Build getter body with Mutex access
        var getterStatements: [CodeBlockItemSyntax] = []

        // Increment call count and record args using withLock
        let argsExpr = Self.buildArgsExpression(parameters: parameters)
        let recordCallStmt = CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: """
_storage.withLock { storage in
    storage.subscript\(suffix)CallCount += 1
    storage.subscript\(suffix)CallArgs.append(\(argsExpr))
}
""")))
        getterStatements.append(recordCallStmt)

        // Call handler
        let handlerCallStmts = buildSendableSubscriptHandlerCallStatements(
            parameters: parameters,
            returnType: returnType,
            hasGenericReturn: hasGenericReturn,
            suffix: suffix
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
            let setterHandlerCall = buildSendableSubscriptSetHandlerCallStatement(parameters: parameters, suffix: suffix)
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
        hasGenericReturn: Bool,
        suffix: String
    ) -> [CodeBlockItemSyntax] {
        let argsExpr = Self.buildArgsExpression(parameters: parameters)
        let handlerCallArgs = parameters.isEmpty ? "" : "\(argsExpr)"

        let returnTypeStr = returnType.description
        let castSuffix = hasGenericReturn ? " as! \(returnTypeStr)" : ""

        let getHandlerStmt = CodeBlockItemSyntax(item: .decl(DeclSyntax(stringLiteral: "let _handler = _storage.withLock { $0.subscript\(suffix)Handler }")))
        let guardStmt = CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: """
guard let _handler else {
    fatalError("\\(Self.self).subscript\(suffix)Handler is not set")
}
""")))
        let returnStmt = CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: "return _handler(\(handlerCallArgs))\(castSuffix)")))
        return [getHandlerStmt, guardStmt, returnStmt]
    }

    private func buildSendableSubscriptSetHandlerCallStatement(parameters: FunctionParameterListSyntax, suffix: String) -> CodeBlockItemSyntax {
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

    // MARK: - Actor Mock Properties

    private func generateActorSubscriptCallCountProperty(suffix: String) -> VariableDeclSyntax {
        VariableDeclSyntax(
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.public)),
                DeclModifierSyntax(name: .keyword(.nonisolated))
            ]),
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier("subscript\(suffix)CallCount")),
                    typeAnnotation: TypeAnnotationSyntax(type: TypeSyntax(stringLiteral: "Int")),
                    accessorBlock: AccessorBlockSyntax(
                        accessors: .accessors(AccessorDeclListSyntax([
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.get),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.subscript\(suffix)CallCount }")))
                                    ])
                                )
                            ),
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.set),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.subscript\(suffix)CallCount = newValue }")))
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
        genericParamNames: Set<String>,
        suffix: String
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
                    pattern: IdentifierPatternSyntax(identifier: .identifier("subscript\(suffix)CallArgs")),
                    typeAnnotation: TypeAnnotationSyntax(type: ArrayTypeSyntax(element: tupleType)),
                    accessorBlock: AccessorBlockSyntax(
                        accessors: .accessors(AccessorDeclListSyntax([
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.get),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.subscript\(suffix)CallArgs }")))
                                    ])
                                )
                            ),
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.set),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.subscript\(suffix)CallArgs = newValue }")))
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
        genericParamNames: Set<String>,
        suffix: String
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
                    pattern: IdentifierPatternSyntax(identifier: .identifier("subscript\(suffix)Handler")),
                    typeAnnotation: TypeAnnotationSyntax(type: TypeSyntax(stringLiteral: handlerType)),
                    accessorBlock: AccessorBlockSyntax(
                        accessors: .accessors(AccessorDeclListSyntax([
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.get),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.subscript\(suffix)Handler }")))
                                    ])
                                )
                            ),
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.set),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.subscript\(suffix)Handler = newValue }")))
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
        genericParamNames: Set<String>,
        suffix: String
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
                    pattern: IdentifierPatternSyntax(identifier: .identifier("subscript\(suffix)SetHandler")),
                    typeAnnotation: TypeAnnotationSyntax(type: TypeSyntax(stringLiteral: handlerType)),
                    accessorBlock: AccessorBlockSyntax(
                        accessors: .accessors(AccessorDeclListSyntax([
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.get),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.subscript\(suffix)SetHandler }")))
                                    ])
                                )
                            ),
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.set),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.subscript\(suffix)SetHandler = newValue }")))
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
        genericParamNames: Set<String>,
        suffix: String
    ) -> SubscriptDeclSyntax {
        // Actor subscripts use the same Sendable pattern
        return generateSendableMockSubscript(subscriptDecl, isGetOnly: isGetOnly, genericParamNames: genericParamNames, suffix: suffix)
    }

}
