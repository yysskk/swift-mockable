import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Initializer Mock Generation

extension MockGenerator {
    /// Generates the members that mock a single `init` requirement: the requirement's
    /// tracking slots and the initializer witness that records the call.
    ///
    /// Unlike methods, initializers have no configurable handler: the recording state lives
    /// on the instance being created, so a per-instance handler could never be set before
    /// the initializer runs. The witness therefore only records that it was invoked and with
    /// which arguments.
    func generateInitializerMock(
        _ initDecl: InitializerDeclSyntax,
        requirement: TrackingRequirement
    ) -> [MemberBlockItemSyntax] {
        var members = trackingMemberItems(for: requirement)

        let witness = generateInitializerWitness(initDecl, identifier: requirement.identifier)
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
        let throwsErrorType = initDecl.signature.effectSpecifiers?.throwsErrorType
        // Initializers are never type members, so their state is instance state.
        let access = trackingAccess(for: .instance)
        let body = buildInitializerBody(
            parameters: parameters,
            identifier: identifier,
            throwsErrorType: throwsErrorType,
            access: access,
            names: WitnessNames(
                parameters: parameters,
                memberNames: access.referencedMembers([
                    MockNaming.callCount(identifier),
                    MockNaming.callArguments(identifier),
                ])
            )
        )

        // A class mock is non-final, so a protocol `init` requirement must be satisfied by a
        // `required` initializer to force subclasses to provide it too. Actors are final and
        // reject `required`. Access uses the member modifier without `open`, since
        // initializers are never `open`.
        let additionalModifiers: [DeclModifierSyntax] = shape.isActor
            ? []
            : [DeclModifierSyntax(name: .keyword(.required))]
        let modifiers = modifiers(for: .member, additional: additionalModifiers)

        return InitializerDeclSyntax(
            modifiers: modifiers,
            optionalMark: initDecl.optionalMark,
            genericParameterClause: initDecl.genericParameterClause,
            signature: initDecl.signature,
            genericWhereClause: initDecl.genericWhereClause,
            body: body
        )
    }

    /// The witness body: evaluate `@autoclosure` arguments once so recording observes
    /// the evaluated value, then record the call the way `access` prescribes. On
    /// lock-backed access the arguments are evaluated before the lock is taken, so a
    /// user-supplied expression never runs while it is held.
    private func buildInitializerBody(
        parameters: FunctionParameterListSyntax,
        identifier: String,
        throwsErrorType: TypeSyntax?,
        access: TrackingAccess,
        names: WitnessNames
    ) -> CodeBlockSyntax {
        var statements: [CodeBlockItemSyntax] = []
        statements.append(contentsOf: ParameterModel.buildParameterBindingStatements(parameters: parameters))
        statements.append(contentsOf: access.recordingStatements(
            identifier: identifier,
            recordedArguments: ParameterModel.buildCallArgumentsExpression(parameters: parameters),
            names: names
        ))
        statements = Self.typedThrowsCatchWrappingAutoclosureEvaluation(
            statements,
            parameters: parameters,
            throwsErrorType: throwsErrorType
        )

        return CodeBlockSyntax(
            leftBrace: .leftBraceToken(trailingTrivia: .newline),
            statements: CodeBlockItemListSyntax(Self.ensureNewlinesBetweenStatements(statements)),
            rightBrace: .rightBraceToken(leadingTrivia: .newline)
        )
    }

    /// Wraps an initializer body in the typed-throws catch when it evaluates a throwing
    /// `@autoclosure` argument, whose `try` would otherwise escape the declared error type.
    /// An initializer has no handler, so this is the only error it can convert.
    private static func typedThrowsCatchWrappingAutoclosureEvaluation(
        _ statements: [CodeBlockItemSyntax],
        parameters: FunctionParameterListSyntax,
        throwsErrorType: TypeSyntax?
    ) -> [CodeBlockItemSyntax] {
        guard
            let errorType = throwsErrorType?.trimmedDescription,
            ParameterModel.hasThrowingAutoclosureParameter(parameters)
        else {
            return statements
        }
        return [buildTypedThrowsCatch(statements: statements, errorType: errorType)]
    }
}

/// Emits an `init` requirement: its tracking slots and the `required init` witness that
/// records the call.
struct InitializerEmitter: RequirementEmitter {
    let generator: MockGenerator
    let decl: InitializerDeclSyntax
    let trackingRequirement: TrackingRequirement

    init(generator: MockGenerator, decl: InitializerDeclSyntax) {
        self.generator = generator
        self.decl = decl
        self.trackingRequirement = generator.initializerTrackingRequirement(for: decl, overloads: generator.overloads)
    }

    var trackingRequirements: [TrackingRequirement] {
        [trackingRequirement]
    }

    func members() -> [MemberBlockItemSyntax] {
        generator.generateInitializerMock(decl, requirement: trackingRequirement)
    }
}
