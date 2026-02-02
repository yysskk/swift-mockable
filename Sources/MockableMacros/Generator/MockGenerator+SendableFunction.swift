import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Sendable Function Mock Generation

extension MockGenerator {
    func generateSendableCallCountProperty(funcName: String) -> VariableDeclSyntax {
        VariableDeclSyntax(
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.public))
            ]),
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier("\(funcName)CallCount")),
                    typeAnnotation: TypeAnnotationSyntax(type: TypeSyntax(stringLiteral: "Int")),
                    accessorBlock: AccessorBlockSyntax(
                        accessors: .accessors(AccessorDeclListSyntax([
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.get),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.\(funcName)CallCount }")))
                                    ])
                                )
                            ),
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.set),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.\(funcName)CallCount = newValue }")))
                                    ])
                                )
                            )
                        ]))
                    )
                )
            ])
        )
    }

    func generateSendableCallArgsProperty(
        funcName: String,
        parameters: FunctionParameterListSyntax,
        genericParamNames: Set<String>
    ) -> VariableDeclSyntax {
        let tupleType = Self.buildParameterTupleType(
            parameters: parameters,
            genericParamNames: genericParamNames
        )

        return VariableDeclSyntax(
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.public))
            ]),
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier("\(funcName)CallArgs")),
                    typeAnnotation: TypeAnnotationSyntax(type: ArrayTypeSyntax(element: tupleType)),
                    accessorBlock: AccessorBlockSyntax(
                        accessors: .accessors(AccessorDeclListSyntax([
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.get),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.\(funcName)CallArgs }")))
                                    ])
                                )
                            ),
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.set),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.\(funcName)CallArgs = newValue }")))
                                    ])
                                )
                            )
                        ]))
                    )
                )
            ])
        )
    }

    func generateSendableHandlerProperty(
        funcName: String,
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
        if isAsync { closureType += " async" }
        if isThrows { closureType += " throws" }
        closureType += " -> \(returnTypeStr)"

        let handlerType = "(@Sendable \(closureType))?"

        return VariableDeclSyntax(
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.public))
            ]),
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier("\(funcName)Handler")),
                    typeAnnotation: TypeAnnotationSyntax(type: TypeSyntax(stringLiteral: handlerType)),
                    accessorBlock: AccessorBlockSyntax(
                        accessors: .accessors(AccessorDeclListSyntax([
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.get),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.\(funcName)Handler }")))
                                    ])
                                )
                            ),
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.set),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.\(funcName)Handler = newValue }")))
                                    ])
                                )
                            )
                        ]))
                    )
                )
            ])
        )
    }

    func generateSendableMockFunction(_ funcDecl: FunctionDeclSyntax, genericParamNames: Set<String>) -> FunctionDeclSyntax {
        let funcName = funcDecl.name.text
        let parameters = funcDecl.signature.parameterClause.parameters
        let returnType = funcDecl.signature.returnClause?.type
        let isAsync = funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil
        let isThrows = funcDecl.signature.effectSpecifiers?.hasThrowsEffect ?? false
        let hasGenericReturn = returnType.map { Self.typeContainsGeneric($0, genericParamNames: genericParamNames) } ?? false

        let argsExpr = Self.buildArgsExpression(parameters: parameters)
        let hasReturnValue = returnType != nil && returnType?.description != "Void"
        let handlerCallArgs = parameters.isEmpty ? "" : "\(argsExpr)"

        // Build the function body using withLock for thread safety
        let closureType = buildClosureType(
            parameters: parameters,
            returnType: returnType,
            isAsync: isAsync,
            isThrows: isThrows,
            genericParamNames: genericParamNames
        )

        var statements: [CodeBlockItemSyntax] = []

        // withLock statement to get handler
        let withLockStmt = CodeBlockItemSyntax(item: .decl(DeclSyntax(stringLiteral: """
let _handler = _storage.withLock { storage -> (@Sendable \(closureType))? in
    storage.\(funcName)CallCount += 1
    storage.\(funcName)CallArgs.append(\(argsExpr))
    return storage.\(funcName)Handler
}
""")))
        statements.append(withLockStmt)

        if hasReturnValue {
            let returnTypeStr = returnType?.description ?? "Void"
            let castSuffix = hasGenericReturn ? " as! \(returnTypeStr)" : ""
            let guardStmt = CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: """
guard let _handler else {
    fatalError("\\(Self.self).\(funcName)Handler is not set")
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

        let body = CodeBlockSyntax(
            leftBrace: .leftBraceToken(trailingTrivia: .newline),
            statements: CodeBlockItemListSyntax(statements),
            rightBrace: .rightBraceToken(leadingTrivia: .newline)
        )

        return FunctionDeclSyntax(
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.public))
            ]),
            name: funcDecl.name,
            genericParameterClause: funcDecl.genericParameterClause,
            signature: funcDecl.signature,
            genericWhereClause: funcDecl.genericWhereClause,
            body: body
        )
    }

    private func buildClosureType(
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
        if isAsync { closureType += " async" }
        if isThrows { closureType += " throws" }
        closureType += " -> \(returnTypeStr)"
        return closureType
    }
}
