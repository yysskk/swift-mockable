import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Initializer Mock Generation

extension MockGenerator {
    /// Generates the members that mock a single `init` requirement: the call-count and
    /// captured-arguments properties and the initializer witness that records the call.
    ///
    /// Unlike methods, initializers have no configurable handler: the recording state lives
    /// on the instance being created, so a per-instance handler could never be set before
    /// the initializer runs. The witness therefore only records that it was invoked and with
    /// which arguments. `identifier` disambiguates overloaded initializers (see
    /// `initializerIdentifier(for:in:)`).
    func generateInitializerMock(
        _ initDecl: InitializerDeclSyntax,
        identifier: String
    ) -> [MemberBlockItemSyntax] {
        var members: [MemberBlockItemSyntax] = []

        let parameters = initDecl.signature.parameterClause.parameters
        let genericParamNames = Self.extractGenericParameterNames(from: initDecl)

        let callCountProperty = generateFunctionStorageProperty(
            name: MockNaming.callCount(identifier),
            type: TypeSyntax(stringLiteral: "Int"),
            initializer: ExprSyntax(IntegerLiteralExprSyntax(literal: .integerLiteral("0"))),
            isTypeMember: false
        )
        members.append(MemberBlockItemSyntax(decl: callCountProperty))

        let tupleType = Self.buildCallArgsTupleType(parameters: parameters, genericParamNames: genericParamNames)
        let callArgsProperty = generateFunctionStorageProperty(
            name: MockNaming.callArgs(identifier),
            type: TypeSyntax(ArrayTypeSyntax(element: tupleType)),
            initializer: ExprSyntax(ArrayExprSyntax(elements: ArrayElementListSyntax([]))),
            isTypeMember: false
        )
        members.append(MemberBlockItemSyntax(decl: callArgsProperty))

        let witness = generateInitializerWitness(initDecl, identifier: identifier)
        members.append(MemberBlockItemSyntax(decl: witness))

        return members
    }

    /// Builds the initializer witness that mirrors the requirement's signature and records
    /// the call into the tracking properties. The requirement's `async`/`throws`, failability
    /// (`init?`), and generic clauses are preserved so the witness satisfies the protocol.
    private func generateInitializerWitness(
        _ initDecl: InitializerDeclSyntax,
        identifier: String
    ) -> InitializerDeclSyntax {
        let parameters = initDecl.signature.parameterClause.parameters
        let body = usesInstanceStorageLock
            ? buildLockBasedInitializerBody(parameters: parameters, identifier: identifier)
            : buildDirectInitializerBody(parameters: parameters, identifier: identifier)

        // A class mock is non-final, so a protocol `init` requirement must be satisfied by a
        // `required` initializer to force subclasses to provide it too. Actors are final and
        // reject `required`. Access uses the member modifier without `open`, since
        // initializers are never `open`.
        let additionalModifiers: [DeclModifierSyntax] = isActor
            ? []
            : [DeclModifierSyntax(name: .keyword(.required))]
        let modifiers = buildModifiers(additional: additionalModifiers, isOverridable: false)

        return InitializerDeclSyntax(
            modifiers: modifiers,
            optionalMark: initDecl.optionalMark,
            genericParameterClause: initDecl.genericParameterClause,
            signature: initDecl.signature,
            genericWhereClause: initDecl.genericWhereClause,
            body: body
        )
    }

    /// The witness body for plain (non-lock-backed) mocks: record directly into the
    /// stored tracking properties.
    private func buildDirectInitializerBody(
        parameters: FunctionParameterListSyntax,
        identifier: String
    ) -> CodeBlockSyntax {
        var statements: [CodeBlockItemSyntax] = []
        // Evaluate @autoclosure arguments once so recording observes the evaluated value,
        // mirroring the method witnesses.
        statements.append(contentsOf: Self.buildAutoclosureEvaluationStatements(parameters: parameters))
        statements.append(
            CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "\(MockNaming.callCount(identifier)) += 1")))
        )
        let argsExpr = Self.buildCallArgsExpression(parameters: parameters)
        statements.append(
            CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "\(MockNaming.callArgs(identifier)).append(\(argsExpr))")))
        )

        return CodeBlockSyntax(
            leftBrace: .leftBraceToken(trailingTrivia: .newline),
            statements: CodeBlockItemListSyntax(Self.ensureNewlinesBetweenStatements(statements)),
            rightBrace: .rightBraceToken(leadingTrivia: .newline)
        )
    }

    /// The witness body for `Sendable`/actor mocks: record inside `withLock` so the tracking
    /// state stays behind the lock. `@autoclosure` arguments are evaluated before taking the
    /// lock so user-supplied expressions never run while it is held.
    private func buildLockBasedInitializerBody(
        parameters: FunctionParameterListSyntax,
        identifier: String
    ) -> CodeBlockSyntax {
        var statements: [CodeBlockItemSyntax] = []
        statements.append(contentsOf: Self.buildAutoclosureEvaluationStatements(parameters: parameters))

        let argsExpr = Self.buildCallArgsExpression(parameters: parameters)
        statements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: """
        \(MockNaming.instanceStorageName).withLock { storage in
            storage.\(MockNaming.callCount(identifier)) += 1
            storage.\(MockNaming.callArgs(identifier)).append(\(argsExpr))
        }
        """))))

        return CodeBlockSyntax(
            leftBrace: .leftBraceToken(trailingTrivia: .newline),
            statements: CodeBlockItemListSyntax(Self.ensureNewlinesBetweenStatements(statements)),
            rightBrace: .rightBraceToken(leadingTrivia: .newline)
        )
    }
}
