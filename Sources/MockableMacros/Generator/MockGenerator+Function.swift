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

        let mockFunction = generateMockFunction(funcDecl, requirement: requirement)
        members.append(MemberBlockItemSyntax(decl: mockFunction))

        return members
    }

    /// The requirement's tracking slots as mock members, one stored or lock-backed
    /// property per `TrackingField`.
    func trackingMemberItems(for requirement: TrackingRequirement) -> [MemberBlockItemSyntax] {
        let access = trackingAccess(for: requirement.scope)
        return requirement.trackingFields(model: access.model).map { field in
            MemberBlockItemSyntax(decl: generateTrackingStorageProperty(
                name: field.name,
                type: field.type,
                initializer: field.initialValue,
                isReadOnly: field.isRecordedByMock,
                scope: requirement.scope,
                leavesMockIsolation: requirement.leavesMockIsolation
            ))
        }
    }

    /// Builds one tracking member (`CallCount`, `CallArguments`, `Handler`, an optional
    /// property, ...): a plain stored property, or a computed property reading and
    /// writing the storage-struct field of the same name through the lock when the
    /// storage model requires it. Shared by the function, variable, subscript, and
    /// initializer generators.
    ///
    /// A read-only member — the call history the mock records itself — cannot be
    /// written from outside the mock: a stored property is `private(set)`, and a
    /// lock-backed one has no setter, since the witness records into the storage struct
    /// directly.
    func generateTrackingStorageProperty(
        name fullName: String,
        type: TypeSyntax,
        initializer: ExprSyntax,
        isReadOnly: Bool,
        scope: MemberScope,
        leavesMockIsolation: Bool
    ) -> VariableDeclSyntax {
        switch trackingAccess(for: scope) {
        case .direct:
            // `private(set)` goes right after the access modifier, as in
            // `public private(set) static var`.
            let setterModifiers = isReadOnly ? [Self.privateSetModifier] : []
            return Self.makeStoredProperty(
                modifiers: modifiers(for: .member, additional: setterModifiers + scope.modifiers),
                name: fullName,
                type: type,
                initializer: initializer
            )

        case .lockBacked(let storageName):
            let additionalModifiers = scope.modifiers + storageBackedMemberModifiers(
                leavesMockIsolation: leavesMockIsolation,
                scope: scope
            )
            if isReadOnly {
                return Self.makeGetOnlyProperty(
                    modifiers: modifiers(for: .member, additional: additionalModifiers),
                    name: fullName,
                    type: type,
                    getterBody: "\(storageName).withLock { $0.\(fullName) }"
                )
            }
            return Self.makeLockBackedProperty(
                modifiers: modifiers(for: .member, additional: additionalModifiers),
                name: fullName,
                type: type,
                storageName: storageName,
                storedName: fullName
            )
        }
    }

    /// The `private(set)` modifier.
    static var privateSetModifier: DeclModifierSyntax {
        DeclModifierSyntax(
            name: .keyword(.private),
            detail: DeclModifierDetailSyntax(detail: .identifier("set"))
        )
    }

    /// Builds the method witness: the requirement's own signature (generics, effects,
    /// and `where` clause preserved so it satisfies the protocol) with a generated body
    /// that records the call and forwards to the handler.
    private func generateMockFunction(
        _ funcDecl: FunctionDeclSyntax,
        requirement: TrackingRequirement
    ) -> FunctionDeclSyntax {
        let identifier = requirement.identifier
        let scope = requirement.scope
        let genericParamNames = TypeErasure.extractGenericParameterNames(from: funcDecl)
        let parameters = funcDecl.signature.parameterClause.parameters
        let returnType = funcDecl.signature.returnClause?.type
        let isAsync = funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil
        // The handler is non-throwing for `rethrows` requirements, so the body invokes
        // it without `try` even though the mock keeps the `rethrows` signature.
        let handlerThrows = (funcDecl.signature.effectSpecifiers?.hasThrowsEffect ?? false)
            && (funcDecl.signature.effectSpecifiers?.isRethrows != true)
        let throwsErrorType = funcDecl.signature.effectSpecifiers?.throwsErrorType
        let hasGenericReturn = returnType.map { TypeErasure.typeContainsGeneric($0, genericParamNames: genericParamNames) } ?? false
        let access = trackingAccess(for: scope)

        let body = buildFunctionBody(
            identifier: identifier,
            parameters: parameters,
            returnType: returnType,
            isAsync: isAsync,
            isThrows: handlerThrows,
            hasGenericReturn: hasGenericReturn,
            genericParamNames: genericParamNames,
            throwsErrorType: throwsErrorType,
            handlerType: requirement.handlerType ?? TrackingRequirement.fallbackHandlerType,
            access: access,
            names: WitnessNames(
                parameters: parameters,
                memberNames: access.referencedMembers([
                    MockNaming.callCount(identifier),
                    MockNaming.callArguments(identifier),
                    MockNaming.handler(identifier),
                ]),
                scope: scope
            )
        )

        return FunctionDeclSyntax(
            attributes: Self.witnessAttributes(of: funcDecl.attributes),
            modifiers: modifiers(for: .member, additional: scope.modifiers),
            name: funcDecl.name,
            genericParameterClause: funcDecl.genericParameterClause,
            signature: funcDecl.signature,
            genericWhereClause: funcDecl.genericWhereClause,
            body: body
        )
    }

    /// The witness body: evaluate `@autoclosure` arguments, record the call and bind
    /// the handler the way `access` prescribes, then invoke the handler — falling back
    /// to a default return or `fatalError` when it is unset, or to a no-op when the
    /// requirement returns nothing. On lock-backed access the handler is invoked
    /// outside the lock, so a user-supplied handler never runs while it is held.
    private func buildFunctionBody(
        identifier: String,
        parameters: FunctionParameterListSyntax,
        returnType: TypeSyntax?,
        isAsync: Bool,
        isThrows: Bool,
        hasGenericReturn: Bool,
        genericParamNames: Set<String>,
        throwsErrorType: TypeSyntax?,
        handlerType: TypeSyntax,
        access: TrackingAccess,
        names: WitnessNames
    ) -> CodeBlockSyntax {
        let errorType = throwsErrorType?.trimmedDescription
        // A throwing `@autoclosure` argument is evaluated with `try` in the requirement's own
        // body, so a typed-throws requirement has to convert that error too: wrap the whole
        // body in one catch rather than only the handler call.
        let wrapsBodyInTypedThrowsCatch = errorType != nil
            && ParameterModel.hasThrowingAutoclosureParameter(parameters)
        let handlerCallErrorType = wrapsBodyInTypedThrowsCatch ? nil : errorType

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

        let handlerCallArguments = buildHandlerCallArguments(parameters: parameters)
        let inOutParams = Self.extractInOutParameters(parameters: parameters, genericParamNames: genericParamNames)
        let invokePrefix = "\(isThrows ? "try " : "")\(isAsync ? "await " : "")"
        if Self.hasReturnValue(returnType) {
            let returnTypeStr = returnType.map { TypeErasure.castTargetType(for: $0) } ?? "Void"
            statements.append(Self.makeUnsetHandlerGuard(
                binding: binding.pattern,
                elseBody: Self.unsetHandlerElseBody(returnType: returnType, handlerName: MockNaming.handler(identifier))
            ))
            statements.append(contentsOf: Self.buildHandlerInvocationStatements(
                invokePrefix: invokePrefix,
                handlerCallArguments: handlerCallArguments,
                inOutParams: inOutParams,
                hasGenericReturn: hasGenericReturn,
                returnTypeStr: returnTypeStr,
                errorType: handlerCallErrorType,
                names: names
            ))
        } else {
            statements.append(Self.buildOptionalHandlerCallStatement(
                handlerBinding: binding.pattern,
                invokePrefix: invokePrefix,
                handlerCallArguments: handlerCallArguments,
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
        let paramTupleType = ParameterModel.buildParameterTupleType(
            parameters: parameters,
            genericParamNames: genericParamNames
        )
        let erasedReturnType = returnType.map { TypeErasure.eraseGenericTypes(in: $0, genericParamNames: genericParamNames) }
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
            parameterClause = ParameterModel.buildSeparateParameterClause(
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
        return parameterClause + AccessorInspection.effectsSuffix(isAsync: isAsync, isThrows: isThrows) + " -> \(returnTypeStr)"
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
        return ParameterModel.buildArgsExpression(parameters: parameters).description
    }

    /// Builds statements for invoking a handler and handling inout write-back (return value path).
    /// Used by both lock-based and direct paths after the handler variable is available.
    /// When `errorType` is set (typed throws, SE-0413), the invocation is wrapped in a
    /// `do`/`catch` that re-throws the caught error as the requirement's error type.
    private static func buildHandlerInvocationStatements(
        invokePrefix: String,
        handlerCallArguments: String,
        inOutParams: [InOutParameter],
        hasGenericReturn: Bool,
        returnTypeStr: String,
        errorType: String? = nil,
        names: WitnessNames
    ) -> [CodeBlockItemSyntax] {
        let castSuffix = hasGenericReturn ? " as! \(returnTypeStr)" : ""
        let call = "\(invokePrefix)\(names.handler)(\(handlerCallArguments))"

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
        handlerCallArguments: String,
        inOutParams: [InOutParameter],
        errorType: String? = nil,
        names: WitnessNames
    ) -> CodeBlockItemSyntax {
        let call = "\(invokePrefix)\(names.handler)(\(handlerCallArguments))"
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
        returnType.map(DefaultReturnValue.returnsAValue) ?? false
    }

    /// An `inout` parameter of a requirement, as the handler and the witness see it.
    /// A stored handler cannot take `inout`, so the mock instead has the handler
    /// *return* the new value and the witness assigns it back after the call.
    struct InOutParameter {
        /// The parameter's internal name, which the witness assigns to.
        let name: String
        /// The type the handler returns the new value as, with generic parameters
        /// erased, e.g. `Any` for `inout T`.
        let erasedType: String
        /// The parameter's own type, which the returned value is cast back to when
        /// erasure changed it.
        let castTarget: String
    }

    /// The requirement's `inout` parameters, with both the erased type the handler
    /// works in and the original type the witness writes back to.
    private static func extractInOutParameters(
        parameters: FunctionParameterListSyntax,
        genericParamNames: Set<String>
    ) -> [InOutParameter] {
        parameters.compactMap { param in
            guard TypeErasure.specifiers(of: param.type).contains("inout") else {
                return nil
            }
            let name = (param.secondName ?? param.firstName).text
            // Both spellings come from the same specifier-free type, so the storage the
            // handler works in and the cast that writes its result back cannot drift.
            let declaredType = TypeErasure.unspecifiedType(param.type)
            let erased = TypeErasure.eraseGenericTypes(in: declaredType, genericParamNames: genericParamNames)
            return InOutParameter(
                name: name,
                erasedType: erased.trimmedDescription,
                castTarget: TypeErasure.castTargetType(for: declaredType.trimmed)
            )
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
        inOutParams: [InOutParameter],
        source: String
    ) -> [String] {
        if inOutParams.count == 1, let first = inOutParams.first {
            return ["\(first.name) = \(source)\(writeBackCastSuffix(for: first))"]
        }
        return inOutParams.map {
            "\($0.name) = \(source).\($0.name)\(writeBackCastSuffix(for: $0))"
        }
    }

    /// The `as!` that converts the handler's erased value back to the parameter's own
    /// type, or nothing when erasure left the type as it was.
    private static func writeBackCastSuffix(
        for param: InOutParameter
    ) -> String {
        param.erasedType == param.castTarget ? "" : " as! \(param.castTarget)"
    }

    /// The write-back assignments as statements.
    private static func buildInOutWriteBackStatements(
        inOutParams: [InOutParameter],
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

/// Emits a method requirement: its tracking slots and the witness that records the
/// call and forwards to the handler.
struct FunctionEmitter: RequirementEmitter {
    let generator: MockGenerator
    let decl: FunctionDeclSyntax
    let trackingRequirement: TrackingRequirement

    init(generator: MockGenerator, decl: FunctionDeclSyntax, requirement: Requirement) {
        self.generator = generator
        self.decl = decl
        self.trackingRequirement = generator.functionTrackingRequirement(
            for: decl,
            scope: requirement.scope,
            leavesMockIsolation: requirement.leavesMockIsolation,
            overloads: generator.overloads
        )
    }

    var trackingRequirements: [TrackingRequirement] {
        [trackingRequirement]
    }

    func members() -> [MemberBlockItemSyntax] {
        generator.generateFunctionMock(decl, requirement: trackingRequirement)
    }
}
