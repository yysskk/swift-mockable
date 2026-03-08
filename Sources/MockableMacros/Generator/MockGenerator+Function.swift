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
        let isTypeMember = Self.isTypeMember(funcDecl.modifiers)
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
            isTypeMember: isTypeMember,
            storageStrategy: storageStrategy
        )
        members.append(MemberBlockItemSyntax(decl: callCountProperty))

        let tupleType = Self.buildParameterTupleType(parameters: parameters, genericParamNames: genericParamNames)
        let callArgsProperty = generateFunctionStorageProperty(
            identifier: identifier,
            propertyName: "CallArgs",
            type: TypeSyntax(ArrayTypeSyntax(element: tupleType)),
            initializer: ExprSyntax(ArrayExprSyntax(elements: ArrayElementListSyntax([]))),
            isTypeMember: isTypeMember,
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
            isTypeMember: isTypeMember,
            storageStrategy: storageStrategy
        )
        members.append(MemberBlockItemSyntax(decl: handlerProperty))

        let mockFunction = generateMockFunction(
            funcDecl,
            identifier: identifier,
            genericParamNames: genericParamNames,
            isTypeMember: isTypeMember,
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
        isTypeMember: Bool,
        storageStrategy: StorageStrategy
    ) -> VariableDeclSyntax {
        let fullName = "\(identifier)\(propertyName)"
        var additionalModifiers = Self.typeMemberModifiers(isTypeMember: isTypeMember)
        let storageName = Self.storagePropertyName(isTypeMember: isTypeMember)
        let usesLockBasedStorage = Self.usesLockBasedStorage(
            isTypeMember: isTypeMember,
            storageStrategy: storageStrategy
        )

        if usesLockBasedStorage {
            if !isTypeMember {
                additionalModifiers.append(contentsOf: storageBackedMemberModifiers())
            }

            return VariableDeclSyntax(
                modifiers: buildModifiers(additional: additionalModifiers),
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
                                            CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "\(storageName).withLock { $0.\(fullName) }")))
                                        ])
                                    )
                                ),
                                AccessorDeclSyntax(
                                    accessorSpecifier: .keyword(.set),
                                    body: CodeBlockSyntax(
                                        statements: CodeBlockItemListSyntax([
                                            CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "\(storageName).withLock { $0.\(fullName) = newValue }")))
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
            modifiers: buildModifiers(additional: additionalModifiers),
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
        isTypeMember: Bool,
        storageStrategy: StorageStrategy
    ) -> FunctionDeclSyntax {
        let parameters = funcDecl.signature.parameterClause.parameters
        let returnType = funcDecl.signature.returnClause?.type
        let isAsync = funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil
        let isThrows = funcDecl.signature.effectSpecifiers?.hasThrowsEffect ?? false
        let hasGenericReturn = returnType.map { Self.typeContainsGeneric($0, genericParamNames: genericParamNames) } ?? false
        let usesLockBasedStorage = Self.usesLockBasedStorage(
            isTypeMember: isTypeMember,
            storageStrategy: storageStrategy
        )

        let body: CodeBlockSyntax
        if usesLockBasedStorage {
            body = buildLockBasedFunctionBody(
                identifier: identifier,
                parameters: parameters,
                returnType: returnType,
                isAsync: isAsync,
                isThrows: isThrows,
                isTypeMember: isTypeMember,
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
                hasGenericReturn: hasGenericReturn,
                genericParamNames: genericParamNames
            )
        }

        return FunctionDeclSyntax(
            modifiers: buildModifiers(additional: Self.typeMemberModifiers(isTypeMember: isTypeMember)),
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
        hasGenericReturn: Bool,
        genericParamNames: Set<String>
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
            hasGenericReturn: hasGenericReturn,
            genericParamNames: genericParamNames
        )
        statements.append(contentsOf: handlerCallStmts)

        return CodeBlockSyntax(
            leftBrace: .leftBraceToken(trailingTrivia: .newline),
            statements: CodeBlockItemListSyntax(Self.ensureNewlinesBetweenStatements(statements)),
            rightBrace: .rightBraceToken(leadingTrivia: .newline)
        )
    }

    private func buildLockBasedFunctionBody(
        identifier: String,
        parameters: FunctionParameterListSyntax,
        returnType: TypeSyntax?,
        isAsync: Bool,
        isThrows: Bool,
        isTypeMember: Bool,
        hasGenericReturn: Bool,
        genericParamNames: Set<String>
    ) -> CodeBlockSyntax {
        let argsExpr = Self.buildArgsExpression(parameters: parameters)
        let hasReturnValue = Self.hasReturnValue(returnType)
        let handlerCallArgs = parameters.isEmpty ? "" : "\(argsExpr)"
        let inOutParams = Self.extractInOutParameters(parameters: parameters, genericParamNames: genericParamNames)
        let storageName = Self.storagePropertyName(isTypeMember: isTypeMember)

        let closureType = buildFunctionClosureType(
            parameters: parameters,
            returnType: returnType,
            isAsync: isAsync,
            isThrows: isThrows,
            genericParamNames: genericParamNames
        )

        var statements: [CodeBlockItemSyntax] = []
        let withLockStmt = CodeBlockItemSyntax(item: .decl(DeclSyntax(stringLiteral: """
let _handler = \(storageName).withLock { storage -> (@Sendable \(closureType))? in
    storage.\(identifier)CallCount += 1
    storage.\(identifier)CallArgs.append(\(argsExpr))
    return storage.\(identifier)Handler
}
""")))
        statements.append(withLockStmt)

        let invokePrefix = "\(isThrows ? "try " : "")\(isAsync ? "await " : "")"
        if hasReturnValue {
            let returnTypeStr = returnType?.description ?? "Void"
            let guardStmt = CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: """
guard let _handler else {
    fatalError("\\(Self.self).\(identifier)Handler is not set")
}
""")))
            statements.append(guardStmt)
            statements.append(contentsOf: Self.buildHandlerInvocationStatements(
                invokePrefix: invokePrefix,
                handlerCallArgs: handlerCallArgs,
                inOutParams: inOutParams,
                hasGenericReturn: hasGenericReturn,
                returnTypeStr: returnTypeStr
            ))
        } else {
            statements.append(Self.buildOptionalHandlerCallStatement(
                handlerBinding: "_handler",
                invokePrefix: invokePrefix,
                handlerCallArgs: handlerCallArgs,
                inOutParams: inOutParams
            ))
        }

        return CodeBlockSyntax(
            leftBrace: .leftBraceToken(trailingTrivia: .newline),
            statements: CodeBlockItemListSyntax(Self.ensureNewlinesBetweenStatements(statements)),
            rightBrace: .rightBraceToken(leadingTrivia: .newline)
        )
    }

    func buildFunctionClosureType(
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
        let hasReturnValue = Self.hasReturnValue(returnType)
        let baseReturnTypeStr = erasedReturnType?.description ?? "Void"
        let returnTypeStr: String
        if let inOutWriteBackType = Self.buildInOutWriteBackType(parameters: parameters, genericParamNames: genericParamNames) {
            if hasReturnValue {
                returnTypeStr = "(returnValue: \(baseReturnTypeStr), inoutArgs: \(inOutWriteBackType))"
            } else {
                returnTypeStr = inOutWriteBackType
            }
        } else {
            returnTypeStr = baseReturnTypeStr
        }

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
        hasGenericReturn: Bool = false,
        genericParamNames: Set<String>
    ) -> [CodeBlockItemSyntax] {
        let argsExpr = Self.buildArgsExpression(parameters: parameters)
        let handlerCallArgs = parameters.isEmpty ? "" : "\(argsExpr)"
        let inOutParams = Self.extractInOutParameters(parameters: parameters, genericParamNames: genericParamNames)
        let invokePrefix = "\(isThrows ? "try " : "")\(isAsync ? "await " : "")"

        let hasReturnValue = Self.hasReturnValue(returnType)

        if hasReturnValue {
            let returnTypeStr = returnType?.description ?? "Void"
            let guardStmt = CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: """
guard let _handler = \(identifier)Handler else {
    fatalError("\\(Self.self).\(identifier)Handler is not set")
}
""")))
            var result: [CodeBlockItemSyntax] = [guardStmt]
            result.append(contentsOf: Self.buildHandlerInvocationStatements(
                invokePrefix: invokePrefix,
                handlerCallArgs: handlerCallArgs,
                inOutParams: inOutParams,
                hasGenericReturn: hasGenericReturn,
                returnTypeStr: returnTypeStr
            ))
            return result
        } else {
            return [Self.buildOptionalHandlerCallStatement(
                handlerBinding: "_handler = \(identifier)Handler",
                invokePrefix: invokePrefix,
                handlerCallArgs: handlerCallArgs,
                inOutParams: inOutParams
            )]
        }
    }

    /// Builds statements for invoking a handler and handling inout write-back (return value path).
    /// Used by both lock-based and direct paths after the handler variable is available.
    private static func buildHandlerInvocationStatements(
        invokePrefix: String,
        handlerCallArgs: String,
        inOutParams: [(name: String, erasedType: String, originalType: String)],
        hasGenericReturn: Bool,
        returnTypeStr: String
    ) -> [CodeBlockItemSyntax] {
        if !inOutParams.isEmpty {
            var result: [CodeBlockItemSyntax] = []
            result.append(CodeBlockItemSyntax(item: .decl(DeclSyntax(stringLiteral: "let _result = \(invokePrefix)_handler(\(handlerCallArgs))"))))
            result.append(contentsOf: buildInOutWriteBackStatements(inOutParams: inOutParams, source: "_result.inoutArgs"))
            let castSuffix = hasGenericReturn ? " as! \(returnTypeStr)" : ""
            result.append(CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: "return _result.returnValue\(castSuffix)"))))
            return result
        }

        let castSuffix = hasGenericReturn ? " as! \(returnTypeStr)" : ""
        return [CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: "return \(invokePrefix)_handler(\(handlerCallArgs))\(castSuffix)")))]
    }

    /// Builds an `if let _handler` statement for optional handler calls (void return).
    /// The `handlerBinding` parameter controls the binding expression:
    /// - Lock-based: `"_handler"` (already bound from withLock)
    /// - Direct: `"_handler = identifierHandler"` (binds from stored property)
    private static func buildOptionalHandlerCallStatement(
        handlerBinding: String,
        invokePrefix: String,
        handlerCallArgs: String,
        inOutParams: [(name: String, erasedType: String, originalType: String)]
    ) -> CodeBlockItemSyntax {
        if !inOutParams.isEmpty {
            var ifBodyLines = [
                "let _writeBack = \(invokePrefix)_handler(\(handlerCallArgs))"
            ]
            ifBodyLines.append(contentsOf: buildInOutWriteBackAssignments(inOutParams: inOutParams, source: "_writeBack"))
            let ifBody = ifBodyLines.map { "    \($0)" }.joined(separator: "\n")
            return CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: """
if let \(handlerBinding) {
\(ifBody)
}
""")))
        }

        return CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: """
if let \(handlerBinding) {
    \(invokePrefix)_handler(\(handlerCallArgs))
}
""")))
    }

    private static func hasReturnValue(_ returnType: TypeSyntax?) -> Bool {
        guard let returnType else {
            return false
        }
        let trimmed = returnType.trimmedDescription
        return trimmed != "Void" && trimmed != "()"
    }

    private static func extractInOutParameters(
        parameters: FunctionParameterListSyntax,
        genericParamNames: Set<String>
    ) -> [(name: String, erasedType: String, originalType: String)] {
        parameters.compactMap { param in
            let typeText = param.type.trimmedDescription
            guard typeText.hasPrefix("inout ") else {
                return nil
            }
            let name = (param.secondName ?? param.firstName).text
            let originalType = String(typeText.dropFirst("inout ".count))
            let strippedType = TypeSyntax(stringLiteral: originalType)
            let erased = eraseGenericTypes(in: strippedType, genericParamNames: genericParamNames)
            return (name: name, erasedType: erased.description, originalType: originalType)
        }
    }

    private static func buildInOutWriteBackType(
        parameters: FunctionParameterListSyntax,
        genericParamNames: Set<String>
    ) -> String? {
        let inOutParams = extractInOutParameters(parameters: parameters, genericParamNames: genericParamNames)
        guard !inOutParams.isEmpty else {
            return nil
        }
        if inOutParams.count == 1, let first = inOutParams.first {
            return first.erasedType
        }
        let elements = inOutParams.map { "\($0.name): \($0.erasedType)" }.joined(separator: ", ")
        return "(\(elements))"
    }

    private static func buildInOutWriteBackAssignments(
        inOutParams: [(name: String, erasedType: String, originalType: String)],
        source: String
    ) -> [String] {
        if inOutParams.count == 1, let first = inOutParams.first {
            let castSuffix = first.erasedType != first.originalType ? " as! \(first.originalType)" : ""
            return ["\(first.name) = \(source)\(castSuffix)"]
        }
        return inOutParams.map {
            let castSuffix = $0.erasedType != $0.originalType ? " as! \($0.originalType)" : ""
            return "\($0.name) = \(source).\($0.name)\(castSuffix)"
        }
    }

    private static func buildInOutWriteBackStatements(
        inOutParams: [(name: String, erasedType: String, originalType: String)],
        source: String
    ) -> [CodeBlockItemSyntax] {
        buildInOutWriteBackAssignments(inOutParams: inOutParams, source: source).map {
            CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: $0)))
        }
    }

    private static func ensureNewlinesBetweenStatements(_ statements: [CodeBlockItemSyntax]) -> [CodeBlockItemSyntax] {
        statements.enumerated().map { index, stmt in
            guard index > 0 else { return stmt }
            var s = stmt
            s.leadingTrivia = .newline
            return s
        }
    }
}
