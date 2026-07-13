import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Function Mock Generation

extension MockGenerator {
    /// Generates the members that mock a single method requirement: the call-count and
    /// captured-arguments properties, the configurable handler, and the witness that
    /// records the call and forwards to the handler. `suffix` disambiguates overloads
    /// that share a base name (see `functionIdentifierSuffix`).
    func generateFunctionMock(
        _ funcDecl: FunctionDeclSyntax,
        suffix: String = ""
    ) -> [MemberBlockItemSyntax] {
        var members: [MemberBlockItemSyntax] = []

        let funcName = funcDecl.name.text
        let identifier = suffix.isEmpty ? funcName : "\(funcName)\(suffix)"
        let isTypeMember = Self.isTypeMember(funcDecl.modifiers)
        let parameters = funcDecl.signature.parameterClause.parameters
        let returnType = funcDecl.signature.returnClause?.type
        let isAsync = funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil
        // A `rethrows` requirement gets a non-throwing handler: a stored handler cannot
        // satisfy `rethrows` (it may only throw through the requirement's own closure
        // parameters), so the handler receives those closures and never throws itself.
        let handlerThrows = (funcDecl.signature.effectSpecifiers?.hasThrowsEffect ?? false)
            && (funcDecl.signature.effectSpecifiers?.isRethrows != true)
        let genericParamNames = Self.extractGenericParameterNames(from: funcDecl)

        let callCountProperty = generateFunctionStorageProperty(
            name: MockNaming.callCount(identifier),
            type: TypeSyntax(stringLiteral: "Int"),
            initializer: ExprSyntax(IntegerLiteralExprSyntax(literal: .integerLiteral("0"))),
            isTypeMember: isTypeMember
        )
        members.append(MemberBlockItemSyntax(decl: callCountProperty))

        let tupleType = Self.buildCallArgsTupleType(parameters: parameters, genericParamNames: genericParamNames)
        let callArgsProperty = generateFunctionStorageProperty(
            name: MockNaming.callArgs(identifier),
            type: TypeSyntax(ArrayTypeSyntax(element: tupleType)),
            initializer: ExprSyntax(ArrayExprSyntax(elements: ArrayElementListSyntax([]))),
            isTypeMember: isTypeMember
        )
        members.append(MemberBlockItemSyntax(decl: callArgsProperty))

        let closureType = buildFunctionClosureType(
            parameters: parameters,
            returnType: returnType,
            isAsync: isAsync,
            isThrows: handlerThrows,
            genericParamNames: genericParamNames
        )
        let handlerProperty = generateFunctionStorageProperty(
            name: MockNaming.handler(identifier),
            type: TypeSyntax(stringLiteral: "(@Sendable \(closureType))?"),
            initializer: ExprSyntax(NilLiteralExprSyntax()),
            isTypeMember: isTypeMember
        )
        members.append(MemberBlockItemSyntax(decl: handlerProperty))

        let mockFunction = generateMockFunction(
            funcDecl,
            identifier: identifier,
            genericParamNames: genericParamNames,
            isTypeMember: isTypeMember
        )
        members.append(MemberBlockItemSyntax(decl: mockFunction))

        return members
    }

    func generateFunctionStorageProperty(
        name fullName: String,
        type: TypeSyntax,
        initializer: ExprSyntax,
        isTypeMember: Bool
    ) -> VariableDeclSyntax {
        var additionalModifiers = Self.typeMemberModifiers(isTypeMember: isTypeMember)
        let storageName = Self.storagePropertyName(isTypeMember: isTypeMember)
        let shouldUseLockBasedStorage = usesLockBasedStorage(isTypeMember: isTypeMember)

        if shouldUseLockBasedStorage {
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
        isTypeMember: Bool
    ) -> FunctionDeclSyntax {
        let parameters = funcDecl.signature.parameterClause.parameters
        let returnType = funcDecl.signature.returnClause?.type
        let isAsync = funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil
        // The handler is non-throwing for `rethrows` requirements, so the body invokes
        // it without `try` even though the mock keeps the `rethrows` signature.
        let handlerThrows = (funcDecl.signature.effectSpecifiers?.hasThrowsEffect ?? false)
            && (funcDecl.signature.effectSpecifiers?.isRethrows != true)
        let throwsErrorType = funcDecl.signature.effectSpecifiers?.throwsErrorType
        let hasGenericReturn = returnType.map { Self.typeContainsGeneric($0, genericParamNames: genericParamNames) } ?? false
        let shouldUseLockBasedStorage = usesLockBasedStorage(isTypeMember: isTypeMember)

        let body: CodeBlockSyntax
        if shouldUseLockBasedStorage {
            body = buildLockBasedFunctionBody(
                identifier: identifier,
                parameters: parameters,
                returnType: returnType,
                isAsync: isAsync,
                isThrows: handlerThrows,
                isTypeMember: isTypeMember,
                hasGenericReturn: hasGenericReturn,
                genericParamNames: genericParamNames,
                throwsErrorType: throwsErrorType
            )
        } else {
            body = buildDirectFunctionBody(
                identifier: identifier,
                parameters: parameters,
                returnType: returnType,
                isAsync: isAsync,
                isThrows: handlerThrows,
                hasGenericReturn: hasGenericReturn,
                genericParamNames: genericParamNames,
                throwsErrorType: throwsErrorType
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
        genericParamNames: Set<String>,
        throwsErrorType: TypeSyntax? = nil
    ) -> CodeBlockSyntax {
        var statements: [CodeBlockItemSyntax] = []
        statements.append(contentsOf: Self.buildAutoclosureEvaluationStatements(parameters: parameters))

        let incrementStmt = InfixOperatorExprSyntax(
            leftOperand: DeclReferenceExprSyntax(baseName: .identifier(MockNaming.callCount(identifier))),
            operator: BinaryOperatorExprSyntax(operator: .binaryOperator("+=")),
            rightOperand: IntegerLiteralExprSyntax(literal: .integerLiteral("1"))
        )
        statements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(incrementStmt))))

        let argsExpr = Self.buildCallArgsExpression(parameters: parameters)
        let appendExpr = FunctionCallExprSyntax(
            calledExpression: MemberAccessExprSyntax(
                base: DeclReferenceExprSyntax(baseName: .identifier(MockNaming.callArgs(identifier))),
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
            genericParamNames: genericParamNames,
            throwsErrorType: throwsErrorType
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
        genericParamNames: Set<String>,
        throwsErrorType: TypeSyntax? = nil
    ) -> CodeBlockSyntax {
        let argsExpr = Self.buildCallArgsExpression(parameters: parameters)
        let hasReturnValue = Self.hasReturnValue(returnType)
        let handlerCallArgs = buildHandlerCallArguments(parameters: parameters)
        let inOutParams = Self.extractInOutParameters(parameters: parameters, genericParamNames: genericParamNames)
        let storageName = Self.storagePropertyName(isTypeMember: isTypeMember)

        let closureType = buildFunctionClosureType(
            parameters: parameters,
            returnType: returnType,
            isAsync: isAsync,
            isThrows: isThrows,
            genericParamNames: genericParamNames
        )
        let errorType = throwsErrorType?.trimmedDescription

        var statements: [CodeBlockItemSyntax] = []
        // Evaluate @autoclosure arguments before taking the lock so user-supplied
        // expressions never run while the storage lock is held.
        statements.append(contentsOf: Self.buildAutoclosureEvaluationStatements(parameters: parameters))
        let withLockStmt = CodeBlockItemSyntax(item: .decl(DeclSyntax(stringLiteral: """
let _handler = \(storageName).withLock { storage -> (@Sendable \(closureType))? in
    storage.\(MockNaming.callCount(identifier)) += 1
    storage.\(MockNaming.callArgs(identifier)).append(\(argsExpr))
    return storage.\(MockNaming.handler(identifier))
}
""")))
        statements.append(withLockStmt)

        let invokePrefix = "\(isThrows ? "try " : "")\(isAsync ? "await " : "")"
        if hasReturnValue {
            let returnTypeStr = returnType?.description ?? "Void"
            let elseBody = Self.defaultReturnStatement(for: returnType)
                ?? "fatalError(\"\\(Self.self).\(MockNaming.handler(identifier)) is not set\")"
            let guardStmt = CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: """
guard let _handler else {
    \(elseBody)
}
""")))
            statements.append(guardStmt)
            statements.append(contentsOf: Self.buildHandlerInvocationStatements(
                invokePrefix: invokePrefix,
                handlerCallArgs: handlerCallArgs,
                inOutParams: inOutParams,
                hasGenericReturn: hasGenericReturn,
                returnTypeStr: returnTypeStr,
                errorType: errorType
            ))
        } else {
            statements.append(Self.buildOptionalHandlerCallStatement(
                handlerBinding: "_handler",
                invokePrefix: invokePrefix,
                handlerCallArgs: handlerCallArgs,
                inOutParams: inOutParams,
                errorType: errorType
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

        // Multiple parameters become individual closure parameters, e.g. `(Int, Int)`,
        // so handlers can be written as `{ a, b in ... }`. A single parameter keeps its
        // own type (`(Int)`); zero parameters produce `()`.
        let parameterClause: String
        if parameters.isEmpty {
            parameterClause = "()"
        } else if parameters.count >= 2 {
            parameterClause = Self.buildSeparateParameterClause(
                parameters: parameters,
                genericParamNames: genericParamNames
            )
        } else {
            parameterClause = "(\(paramTupleType.description))"
        }
        var closureType = parameterClause
        if isAsync {
            closureType += " async"
        }
        if isThrows {
            // The handler is untyped-throwing even for typed-throws (`throws(E)`)
            // requirements: a typed-throws function value would need the Swift 6 runtime
            // (macOS 15+) and cannot name a method's generic error type at storage scope.
            // The generated body re-throws the typed error via a `catch` (see buildTypedThrowsCatch).
            closureType += " throws"
        }
        closureType += " -> \(returnTypeStr)"
        return closureType
    }

    /// Builds the argument string passed to `_handler(...)` in the generated method body.
    /// - multiple parameters (>= 2): `a, b`  -> `_handler(a, b)`
    /// - single parameter:           the bare name -> `_handler(id)`
    /// - zero parameters:            `""`    -> `_handler()`
    ///
    /// Also reused for subscript getter handlers, whose parameter shaping is identical.
    func buildHandlerCallArguments(parameters: FunctionParameterListSyntax) -> String {
        if parameters.isEmpty {
            return ""
        }
        if parameters.count >= 2 {
            return parameters
                .map { ($0.secondName ?? $0.firstName).text }
                .joined(separator: ", ")
        }
        return Self.buildArgsExpression(parameters: parameters).description
    }

    private func buildHandlerCallStatements(
        identifier: String,
        parameters: FunctionParameterListSyntax,
        returnType: TypeSyntax?,
        isAsync: Bool,
        isThrows: Bool,
        hasGenericReturn: Bool = false,
        genericParamNames: Set<String>,
        throwsErrorType: TypeSyntax? = nil
    ) -> [CodeBlockItemSyntax] {
        let handlerCallArgs = buildHandlerCallArguments(parameters: parameters)
        let inOutParams = Self.extractInOutParameters(parameters: parameters, genericParamNames: genericParamNames)
        let invokePrefix = "\(isThrows ? "try " : "")\(isAsync ? "await " : "")"
        let errorType = throwsErrorType?.trimmedDescription

        let hasReturnValue = Self.hasReturnValue(returnType)

        if hasReturnValue {
            let returnTypeStr = returnType?.description ?? "Void"
            let elseBody = Self.defaultReturnStatement(for: returnType)
                ?? "fatalError(\"\\(Self.self).\(MockNaming.handler(identifier)) is not set\")"
            let guardStmt = CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: """
guard let _handler = \(MockNaming.handler(identifier)) else {
    \(elseBody)
}
""")))
            var result: [CodeBlockItemSyntax] = [guardStmt]
            result.append(contentsOf: Self.buildHandlerInvocationStatements(
                invokePrefix: invokePrefix,
                handlerCallArgs: handlerCallArgs,
                inOutParams: inOutParams,
                hasGenericReturn: hasGenericReturn,
                returnTypeStr: returnTypeStr,
                errorType: errorType
            ))
            return result
        } else {
            return [Self.buildOptionalHandlerCallStatement(
                handlerBinding: "_handler = \(MockNaming.handler(identifier))",
                invokePrefix: invokePrefix,
                handlerCallArgs: handlerCallArgs,
                inOutParams: inOutParams,
                errorType: errorType
            )]
        }
    }

    /// Builds statements for invoking a handler and handling inout write-back (return value path).
    /// Used by both lock-based and direct paths after the handler variable is available.
    /// When `errorType` is set (typed throws, SE-0413), the invocation is wrapped in a
    /// `do`/`catch` that re-throws the caught error as the requirement's error type.
    private static func buildHandlerInvocationStatements(
        invokePrefix: String,
        handlerCallArgs: String,
        inOutParams: [(name: String, erasedType: String, originalType: String)],
        hasGenericReturn: Bool,
        returnTypeStr: String,
        errorType: String? = nil
    ) -> [CodeBlockItemSyntax] {
        let castSuffix = hasGenericReturn ? " as! \(returnTypeStr)" : ""

        if let errorType {
            var innerLines: [String] = []
            if !inOutParams.isEmpty {
                innerLines.append("let _result = \(invokePrefix)_handler(\(handlerCallArgs))")
                innerLines.append(contentsOf: buildInOutWriteBackAssignments(inOutParams: inOutParams, source: "_result.inoutArgs"))
                innerLines.append("return _result.returnValue\(castSuffix)")
            } else {
                innerLines.append("return \(invokePrefix)_handler(\(handlerCallArgs))\(castSuffix)")
            }
            return [buildTypedThrowsCatch(innerLines: innerLines, errorType: errorType)]
        }

        if !inOutParams.isEmpty {
            var result: [CodeBlockItemSyntax] = []
            result.append(CodeBlockItemSyntax(item: .decl(DeclSyntax(stringLiteral: "let _result = \(invokePrefix)_handler(\(handlerCallArgs))"))))
            result.append(contentsOf: buildInOutWriteBackStatements(inOutParams: inOutParams, source: "_result.inoutArgs"))
            result.append(CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: "return _result.returnValue\(castSuffix)"))))
            return result
        }

        return [CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: "return \(invokePrefix)_handler(\(handlerCallArgs))\(castSuffix)")))]
    }

    /// Wraps `innerLines` in a `do { ... } catch { throw error as! ErrorType }` statement,
    /// used to re-throw a typed-throws error from an untyped-throwing handler.
    static func buildTypedThrowsCatch(innerLines: [String], errorType: String) -> CodeBlockItemSyntax {
        let body = innerLines.map { "    \($0)" }.joined(separator: "\n")
        return CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: """
        do {
        \(body)
        } catch {
            throw error as! \(errorType)
        }
        """)))
    }

    /// Builds an `if let _handler` statement for optional handler calls (void return).
    /// The `handlerBinding` parameter controls the binding expression:
    /// - Lock-based: `"_handler"` (already bound from withLock)
    /// - Direct: `"_handler = identifierHandler"` (binds from stored property)
    private static func buildOptionalHandlerCallStatement(
        handlerBinding: String,
        invokePrefix: String,
        handlerCallArgs: String,
        inOutParams: [(name: String, erasedType: String, originalType: String)],
        errorType: String? = nil
    ) -> CodeBlockItemSyntax {
        var ifBodyLines: [String]
        if !inOutParams.isEmpty {
            ifBodyLines = ["let _writeBack = \(invokePrefix)_handler(\(handlerCallArgs))"]
            ifBodyLines.append(contentsOf: buildInOutWriteBackAssignments(inOutParams: inOutParams, source: "_writeBack"))
        } else {
            ifBodyLines = ["\(invokePrefix)_handler(\(handlerCallArgs))"]
        }

        // Typed throws: wrap the handler call in a `do`/`catch` that re-throws the
        // caught error as the requirement's error type.
        if let errorType {
            let doBody = ifBodyLines.map { "        \($0)" }.joined(separator: "\n")
            return CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: """
if let \(handlerBinding) {
    do {
\(doBody)
    } catch {
        throw error as! \(errorType)
    }
}
""")))
        }

        let ifBody = ifBodyLines.map { "    \($0)" }.joined(separator: "\n")
        return CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: """
if let \(handlerBinding) {
\(ifBody)
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

    static func ensureNewlinesBetweenStatements(_ statements: [CodeBlockItemSyntax]) -> [CodeBlockItemSyntax] {
        statements.enumerated().map { index, stmt in
            guard index > 0 else { return stmt }
            var s = stmt
            s.leadingTrivia = .newline
            return s
        }
    }
}
