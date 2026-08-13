import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Function Mock Generation

extension MockGenerator {
    /// Generates the members that mock a single method requirement: the requirement's
    /// tracking slots (call count, captured arguments, handler) and the witness that
    /// records the call and forwards to the handler.
    func generateFunctionMock(
        _ funcDecl: FunctionDeclSyntax,
        requirement: TrackingRequirement
    ) -> [MemberBlockItemSyntax] {
        var members = trackingMemberItems(for: requirement)

        let mockFunction = generateMockFunction(
            funcDecl,
            identifier: requirement.identifier,
            genericParamNames: Self.extractGenericParameterNames(from: funcDecl),
            isTypeMember: requirement.isTypeMember
        )
        members.append(MemberBlockItemSyntax(decl: mockFunction))

        return members
    }

    /// The requirement's tracking slots as mock members, one stored or lock-backed
    /// property per `TrackingField`.
    func trackingMemberItems(for requirement: TrackingRequirement) -> [MemberBlockItemSyntax] {
        requirement.trackingFields(model: .direct).map { field in
            MemberBlockItemSyntax(decl: generateTrackingStorageProperty(
                name: field.name,
                type: field.type,
                initializer: field.initialValue,
                isTypeMember: requirement.isTypeMember
            ))
        }
    }

    /// Builds one tracking member (`CallCount`, `CallArgs`, `Handler`, ...): a plain
    /// stored property, or a lock-backed computed property when the storage model
    /// requires it. Shared by the function, variable, subscript, and initializer
    /// generators.
    func generateTrackingStorageProperty(
        name fullName: String,
        type: TypeSyntax,
        initializer: ExprSyntax,
        isTypeMember: Bool
    ) -> VariableDeclSyntax {
        var additionalModifiers = Self.typeMemberModifiers(isTypeMember: isTypeMember)

        if usesLockBasedStorage(isTypeMember: isTypeMember) {
            if !isTypeMember {
                additionalModifiers.append(contentsOf: storageBackedMemberModifiers())
            }

            return Self.makeLockBackedProperty(
                modifiers: buildModifiers(additional: additionalModifiers),
                name: fullName,
                type: type,
                storageName: Self.storagePropertyName(isTypeMember: isTypeMember),
                storedName: fullName
            )
        }

        return Self.makeStoredProperty(
            modifiers: buildModifiers(additional: additionalModifiers),
            name: fullName,
            type: type,
            initializer: initializer
        )
    }

    /// Builds the method witness: the requirement's own signature (generics, effects,
    /// and `where` clause preserved so it satisfies the protocol) with a generated body
    /// that records the call and forwards to the handler.
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
                throwsErrorType: throwsErrorType,
                names: WitnessNames(
                    parameters: parameters,
                    memberNames: [Self.storagePropertyName(isTypeMember: isTypeMember)],
                    isTypeMember: isTypeMember
                )
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
                throwsErrorType: throwsErrorType,
                names: WitnessNames(
                    parameters: parameters,
                    memberNames: [
                        MockNaming.callCount(identifier),
                        MockNaming.callArgs(identifier),
                        MockNaming.handler(identifier),
                    ],
                    isTypeMember: isTypeMember
                )
            )
        }

        return FunctionDeclSyntax(
            attributes: Self.witnessAttributes(of: funcDecl.attributes),
            modifiers: buildModifiers(additional: Self.typeMemberModifiers(isTypeMember: isTypeMember)),
            name: funcDecl.name,
            genericParameterClause: funcDecl.genericParameterClause,
            signature: funcDecl.signature,
            genericWhereClause: funcDecl.genericWhereClause,
            body: body
        )
    }

    /// The witness body for plain mocks: evaluate `@autoclosure` arguments, record the
    /// call into the stored tracking properties, then invoke the handler.
    private func buildDirectFunctionBody(
        identifier: String,
        parameters: FunctionParameterListSyntax,
        returnType: TypeSyntax?,
        isAsync: Bool,
        isThrows: Bool,
        hasGenericReturn: Bool,
        genericParamNames: Set<String>,
        throwsErrorType: TypeSyntax? = nil,
        names: WitnessNames
    ) -> CodeBlockSyntax {
        // A throwing `@autoclosure` argument is evaluated with `try` in the requirement's own
        // body, so a typed-throws requirement has to convert that error too: wrap the whole
        // body in one catch rather than only the handler call.
        let errorType = throwsErrorType?.trimmedDescription
        let wrapsBodyInTypedThrowsCatch = errorType != nil
            && Self.hasThrowingAutoclosureParameter(parameters)

        var statements: [CodeBlockItemSyntax] = []
        statements.append(contentsOf: Self.buildAutoclosureEvaluationStatements(parameters: parameters))

        statements.append(contentsOf: Self.makeCallRecordingStatements(
            identifier: identifier,
            parameters: parameters,
            names: names
        ))

        let handlerCallStmts = buildHandlerCallStatements(
            identifier: identifier,
            parameters: parameters,
            returnType: returnType,
            isAsync: isAsync,
            isThrows: isThrows,
            hasGenericReturn: hasGenericReturn,
            genericParamNames: genericParamNames,
            throwsErrorType: wrapsBodyInTypedThrowsCatch ? nil : throwsErrorType,
            names: names
        )
        statements.append(contentsOf: handlerCallStmts)

        if wrapsBodyInTypedThrowsCatch, let errorType {
            statements = [Self.buildTypedThrowsCatch(statements: statements, errorType: errorType)]
        }

        return CodeBlockSyntax(
            leftBrace: .leftBraceToken(trailingTrivia: .newline),
            statements: CodeBlockItemListSyntax(Self.ensureNewlinesBetweenStatements(statements)),
            rightBrace: .rightBraceToken(leadingTrivia: .newline)
        )
    }

    /// The witness body for `Sendable`/actor mocks and type members: record the call and
    /// read the handler in a single `withLock`, then invoke the handler outside the lock
    /// so a user-supplied handler never runs while it is held.
    private func buildLockBasedFunctionBody(
        identifier: String,
        parameters: FunctionParameterListSyntax,
        returnType: TypeSyntax?,
        isAsync: Bool,
        isThrows: Bool,
        isTypeMember: Bool,
        hasGenericReturn: Bool,
        genericParamNames: Set<String>,
        throwsErrorType: TypeSyntax? = nil,
        names: WitnessNames
    ) -> CodeBlockSyntax {
        let argsExpr = Self.buildCallArgsExpression(parameters: parameters)
        let hasReturnValue = Self.hasReturnValue(returnType)
        let handlerCallArgs = buildHandlerCallArguments(parameters: parameters)
        let inOutParams = Self.extractInOutParameters(parameters: parameters, genericParamNames: genericParamNames)
        let storageName = names.member(Self.storagePropertyName(isTypeMember: isTypeMember))

        let closureType = buildFunctionClosureType(
            parameters: parameters,
            returnType: returnType,
            isAsync: isAsync,
            isThrows: isThrows,
            genericParamNames: genericParamNames
        )
        let errorType = throwsErrorType?.trimmedDescription
        // A throwing `@autoclosure` argument is evaluated with `try` in the requirement's own
        // body, so a typed-throws requirement has to convert that error too: wrap the whole
        // body in one catch rather than only the handler call.
        let wrapsBodyInTypedThrowsCatch = errorType != nil
            && Self.hasThrowingAutoclosureParameter(parameters)
        let handlerCallErrorType = wrapsBodyInTypedThrowsCatch ? nil : errorType

        var statements: [CodeBlockItemSyntax] = []
        // Evaluate @autoclosure arguments before taking the lock so user-supplied
        // expressions never run while the storage lock is held.
        statements.append(contentsOf: Self.buildAutoclosureEvaluationStatements(parameters: parameters))
        let withLockStmt = CodeBlockItemSyntax(item: .decl(DeclSyntax(stringLiteral: """
let \(names.handler) = \(storageName).withLock { \(names.storage) -> (@Sendable \(closureType))? in
    \(names.storage).\(MockNaming.callCount(identifier)) += 1
    \(names.storage).\(MockNaming.callArgs(identifier)).append(\(argsExpr))
    return \(names.storage).\(MockNaming.handler(identifier))
}
""")))
        statements.append(withLockStmt)

        let invokePrefix = "\(isThrows ? "try " : "")\(isAsync ? "await " : "")"
        if hasReturnValue {
            let returnTypeStr = returnType.map { Self.castTargetType(for: $0) } ?? "Void"
            statements.append(Self.makeUnsetHandlerGuard(
                binding: names.handler,
                elseBody: Self.unsetHandlerElseBody(returnType: returnType, handlerName: MockNaming.handler(identifier))
            ))
            statements.append(contentsOf: Self.buildHandlerInvocationStatements(
                invokePrefix: invokePrefix,
                handlerCallArgs: handlerCallArgs,
                inOutParams: inOutParams,
                hasGenericReturn: hasGenericReturn,
                returnTypeStr: returnTypeStr,
                errorType: handlerCallErrorType,
                names: names
            ))
        } else {
            statements.append(Self.buildOptionalHandlerCallStatement(
                handlerBinding: names.handler,
                invokePrefix: invokePrefix,
                handlerCallArgs: handlerCallArgs,
                inOutParams: inOutParams,
                errorType: handlerCallErrorType,
                names: names
            ))
        }

        if wrapsBodyInTypedThrowsCatch, let errorType {
            statements = [Self.buildTypedThrowsCatch(statements: statements, errorType: errorType)]
        }

        return CodeBlockSyntax(
            leftBrace: .leftBraceToken(trailingTrivia: .newline),
            statements: CodeBlockItemListSyntax(Self.ensureNewlinesBetweenStatements(statements)),
            rightBrace: .rightBraceToken(leadingTrivia: .newline)
        )
    }

    /// The handler's closure type, e.g. `(Int, String) async throws -> User`. Parameters
    /// are stored individually (so handlers read as `{ a, b in ... }`), generic parameters
    /// are erased, and `inout` write-back values are folded into the return type.
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
        // The handler is untyped-throwing even for typed-throws (`throws(E)`)
        // requirements: a typed-throws function value would need the Swift 6 runtime
        // (macOS 15+) and cannot name a method's generic error type at storage scope.
        // The generated body re-throws the typed error via a `catch` (see buildTypedThrowsCatch).
        return parameterClause + Self.effectsSuffix(isAsync: isAsync, isThrows: isThrows) + " -> \(returnTypeStr)"
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

    /// The direct path's handler invocation: a guard binding the stored handler (falling
    /// back to a default return or `fatalError`) plus the call itself, or a plain
    /// `if let` no-op when the requirement returns nothing.
    private func buildHandlerCallStatements(
        identifier: String,
        parameters: FunctionParameterListSyntax,
        returnType: TypeSyntax?,
        isAsync: Bool,
        isThrows: Bool,
        hasGenericReturn: Bool = false,
        genericParamNames: Set<String>,
        throwsErrorType: TypeSyntax? = nil,
        names: WitnessNames
    ) -> [CodeBlockItemSyntax] {
        let handlerCallArgs = buildHandlerCallArguments(parameters: parameters)
        let inOutParams = Self.extractInOutParameters(parameters: parameters, genericParamNames: genericParamNames)
        let invokePrefix = "\(isThrows ? "try " : "")\(isAsync ? "await " : "")"
        let errorType = throwsErrorType?.trimmedDescription
        let handlerBinding = "\(names.handler) = \(names.member(MockNaming.handler(identifier)))"

        let hasReturnValue = Self.hasReturnValue(returnType)

        if hasReturnValue {
            let returnTypeStr = returnType.map { Self.castTargetType(for: $0) } ?? "Void"
            let guardStmt = Self.makeUnsetHandlerGuard(
                binding: handlerBinding,
                elseBody: Self.unsetHandlerElseBody(returnType: returnType, handlerName: MockNaming.handler(identifier))
            )
            var result: [CodeBlockItemSyntax] = [guardStmt]
            result.append(contentsOf: Self.buildHandlerInvocationStatements(
                invokePrefix: invokePrefix,
                handlerCallArgs: handlerCallArgs,
                inOutParams: inOutParams,
                hasGenericReturn: hasGenericReturn,
                returnTypeStr: returnTypeStr,
                errorType: errorType,
                names: names
            ))
            return result
        } else {
            return [Self.buildOptionalHandlerCallStatement(
                handlerBinding: handlerBinding,
                invokePrefix: invokePrefix,
                handlerCallArgs: handlerCallArgs,
                inOutParams: inOutParams,
                errorType: errorType,
                names: names
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
        errorType: String? = nil,
        names: WitnessNames
    ) -> [CodeBlockItemSyntax] {
        let castSuffix = hasGenericReturn ? " as! \(returnTypeStr)" : ""
        let call = "\(invokePrefix)\(names.handler)(\(handlerCallArgs))"

        if let errorType {
            var innerLines: [String] = []
            if !inOutParams.isEmpty {
                innerLines.append("let \(names.result) = \(call)")
                innerLines.append(contentsOf: buildInOutWriteBackAssignments(inOutParams: inOutParams, source: "\(names.result).inoutArgs"))
                innerLines.append("return \(names.result).returnValue\(castSuffix)")
            } else {
                innerLines.append("return \(call)\(castSuffix)")
            }
            return [buildTypedThrowsCatch(innerLines: innerLines, errorType: errorType)]
        }

        if !inOutParams.isEmpty {
            var result: [CodeBlockItemSyntax] = []
            result.append(CodeBlockItemSyntax(item: .decl(DeclSyntax(stringLiteral: "let \(names.result) = \(call)"))))
            result.append(contentsOf: buildInOutWriteBackStatements(inOutParams: inOutParams, source: "\(names.result).inoutArgs"))
            result.append(CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: "return \(names.result).returnValue\(castSuffix)"))))
            return result
        }

        return [CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: "return \(call)\(castSuffix)")))]
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

    /// Wraps whole statements in the typed-throws catch, keeping each statement's own
    /// indentation. Used when the conversion has to cover more than the handler call.
    static func buildTypedThrowsCatch(
        statements: [CodeBlockItemSyntax],
        errorType: String
    ) -> CodeBlockItemSyntax {
        let lines = statements.flatMap { statement in
            statement.trimmedDescription
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
        }
        return buildTypedThrowsCatch(innerLines: lines, errorType: errorType)
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
        errorType: String? = nil,
        names: WitnessNames
    ) -> CodeBlockItemSyntax {
        let call = "\(invokePrefix)\(names.handler)(\(handlerCallArgs))"
        var ifBodyLines: [String]
        if !inOutParams.isEmpty {
            ifBodyLines = ["let \(names.writeBack) = \(call)"]
            ifBodyLines.append(contentsOf: buildInOutWriteBackAssignments(inOutParams: inOutParams, source: names.writeBack))
        } else {
            ifBodyLines = [call]
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

    /// Whether the requirement returns something the witness must produce. A `Void`
    /// return (however spelled) takes the no-return-value path, where an unset handler
    /// is simply a no-op rather than a `fatalError`.
    private static func hasReturnValue(_ returnType: TypeSyntax?) -> Bool {
        guard let returnType else {
            return false
        }
        let trimmed = returnType.trimmedDescription
        return trimmed != "Void" && trimmed != "()"
    }

    /// The requirement's `inout` parameters, with both the erased type the handler
    /// works in and the original type the witness writes back to. A stored handler
    /// cannot take `inout`, so the mock instead has the handler *return* the new
    /// values and assigns them after the call.
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

    /// The type the handler returns so the witness can write back `inout` arguments:
    /// the bare type for one such parameter, a labeled tuple for several, and `nil`
    /// when the requirement has none.
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

    /// The assignments that copy the handler's returned values back into the `inout`
    /// arguments, casting back from the erased type where erasure changed it.
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

    /// The write-back assignments as statements.
    private static func buildInOutWriteBackStatements(
        inOutParams: [(name: String, erasedType: String, originalType: String)],
        source: String
    ) -> [CodeBlockItemSyntax] {
        buildInOutWriteBackAssignments(inOutParams: inOutParams, source: source).map {
            CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: $0)))
        }
    }

    /// The attributes a requirement's witness keeps.
    ///
    /// Witnesses are built from scratch rather than by editing the requirement, so an
    /// attribute is carried over only when it means the same thing on the mock. That is
    /// `@discardableResult`, which describes how callers may use the result and would
    /// otherwise leave every discarding call site with an unused-result warning. Others
    /// are deliberately dropped: `@available(*, deprecated)` marks the requirement, not
    /// the mock a test calls, and an availability range is inherited from the expansion
    /// site already.
    static func witnessAttributes(of attributes: AttributeListSyntax) -> AttributeListSyntax {
        let carried: Set<String> = ["discardableResult"]
        let elements = attributes.compactMap { element -> AttributeListSyntax.Element? in
            guard case .attribute(let attribute) = element,
                  carried.contains(attribute.attributeName.trimmedDescription) else {
                return nil
            }
            // The requirement's own layout does not apply where the witness is emitted,
            // so the attribute is re-laid out on a line of its own.
            return .attribute(attribute.trimmed.with(\.trailingTrivia, .newline))
        }
        return AttributeListSyntax(elements)
    }

    /// Puts each statement after the first on its own line. Statements assembled from
    /// separate builders carry no leading trivia, so without this the formatter would
    /// run them together.
    static func ensureNewlinesBetweenStatements(_ statements: [CodeBlockItemSyntax]) -> [CodeBlockItemSyntax] {
        statements.enumerated().map { index, stmt in
            guard index > 0 else { return stmt }
            var s = stmt
            s.leadingTrivia = .newline
            return s
        }
    }
}
