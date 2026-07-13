import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Initializer Mock Generation

extension MockGenerator {
    /// Generates the members that mock a single `init` requirement: the call-count and
    /// captured-arguments properties and the `required init` witness that records the call.
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

    /// Builds the `required init` witness that mirrors the requirement's signature and records
    /// the call into the tracking properties. The requirement's `async`/`throws`, failability
    /// (`init?`), and generic clauses are preserved so the witness satisfies the protocol.
    private func generateInitializerWitness(
        _ initDecl: InitializerDeclSyntax,
        identifier: String
    ) -> InitializerDeclSyntax {
        let parameters = initDecl.signature.parameterClause.parameters

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

        let body = CodeBlockSyntax(
            leftBrace: .leftBraceToken(trailingTrivia: .newline),
            statements: CodeBlockItemListSyntax(Self.ensureNewlinesBetweenStatements(statements)),
            rightBrace: .rightBraceToken(leadingTrivia: .newline)
        )

        // A protocol `init` requirement must be satisfied by a `required` initializer so that
        // subclasses of the (non-final) mock also provide it. Access uses the member modifier
        // without `open`, since initializers are never `open`.
        let modifiers = buildModifiers(
            additional: [DeclModifierSyntax(name: .keyword(.required))],
            isOverridable: false
        )

        return InitializerDeclSyntax(
            modifiers: modifiers,
            optionalMark: initDecl.optionalMark,
            genericParameterClause: initDecl.genericParameterClause,
            signature: initDecl.signature,
            genericWhereClause: initDecl.genericWhereClause,
            body: body
        )
    }
}
