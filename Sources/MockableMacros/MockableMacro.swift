import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// The implementation of the `@Mockable` attached peer macro.
///
/// Applied to a protocol, it generates a `<Protocol>Mock` class (wrapped in `#if DEBUG`)
/// that conforms to the protocol and records calls, captures arguments, and exposes a
/// configurable handler for every requirement. The protocol's shape drives the output:
/// `Sendable`/`Actor` conformances select a lock-backed storage model, an inherited
/// protocol produces a subclassing mock, and unsupported members are reported as
/// diagnostics (see ``MockableError``) instead of generating invalid code.
public struct MockableMacro: PeerMacro {
    /// Generates the mock class peer for a `@Mockable` protocol.
    ///
    /// Returns an empty array (emitting diagnostics) when the declaration is not a
    /// protocol, when the macro is given arguments, or when a member cannot be mocked.
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let protocolDecl = declaration.as(ProtocolDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: Syntax(node), message: MockableError.notAProtocol))
            return []
        }

        // Protocol-level conformance flags drive both diagnostics and code generation.
        let isSendable = protocolDecl.inheritanceClause?.inheritedTypes.contains { inherited in
            inherited.type.trimmedDescription == "Sendable"
        } ?? false

        let hasSendableAttribute = protocolDecl.attributes.contains { attr in
            if case .attribute(let attributeSyntax) = attr {
                return attributeSyntax.attributeName.trimmedDescription == "Sendable"
            }
            return false
        }

        // Check if the protocol inherits from Actor
        let isActor = protocolDecl.inheritanceClause?.inheritedTypes.contains { inherited in
            inherited.type.trimmedDescription == "Actor"
        } ?? false

        // Extract parent protocol names (excluding well-known non-protocol types)
        let knownNonParentProtocols: Set<String> = ["Sendable", "Actor", "AnyObject", "AnyActor"]
        let parentProtocolNames: [String] = protocolDecl.inheritanceClause?.inheritedTypes
            .map { $0.type.trimmedDescription }
            .filter { !knownNonParentProtocols.contains($0) }
            ?? []

        let hasInvalidArguments = diagnoseArguments(from: node, in: context)
        let hasUnsupportedMembers = diagnoseUnsupportedMembers(in: protocolDecl.memberBlock.members, context: context)
        // An `init` declared directly on an inheriting protocol is not yet mockable: the
        // witness would need to chain through the parent mock's initializer, which the macro
        // cannot see. Initializers inherited from the parent still work, since the child mock
        // inherits the parent mock's `required init`.
        let hasUnsupportedInitializers = diagnoseInitializerContext(
            in: protocolDecl.memberBlock.members,
            isUnsupportedContext: !parentProtocolNames.isEmpty,
            context: context
        )
        guard !hasInvalidArguments, !hasUnsupportedMembers, !hasUnsupportedInitializers else {
            return []
        }

        let protocolName = protocolDecl.name.text
        let mockClassName = MockNaming.mockTypeName(forProtocol: protocolName)

        // Check if the protocol has @MainActor attribute
        let isMainActor = protocolDecl.attributes.contains { attr in
            if case .attribute(let attributeSyntax) = attr {
                return attributeSyntax.attributeName.trimmedDescription == "MainActor"
            }
            return false
        }

        let parentMockClassName: String? = parentProtocolNames.first.map { MockNaming.mockTypeName(forProtocol: $0) }

        let members = protocolDecl.memberBlock.members

        // Extract access level from the protocol declaration
        let accessLevel = AccessLevel.from(protocolDecl: protocolDecl)

        let generator = MockGenerator(
            protocolName: protocolName,
            mockClassName: mockClassName,
            members: members,
            isSendable: isSendable || hasSendableAttribute,
            isActor: isActor,
            isMainActor: isMainActor,
            accessLevel: accessLevel,
            parentMockClassName: parentMockClassName
        )

        let mockClass = try generator.generate()

        // Wrap in #if DEBUG
        let ifConfigDecl = IfConfigDeclSyntax(
            clauses: IfConfigClauseListSyntax([
                IfConfigClauseSyntax(
                    poundKeyword: .poundIfToken(),
                    condition: DeclReferenceExprSyntax(baseName: .identifier("DEBUG")),
                    elements: .decls(MemberBlockItemListSyntax([
                        MemberBlockItemSyntax(decl: mockClass)
                    ]))
                )
            ])
        )

        return [DeclSyntax(ifConfigDecl)]
    }

    /// Validates that `@Mockable` is used without arguments.
    private static func diagnoseArguments(
        from node: AttributeSyntax,
        in context: some MacroExpansionContext
    ) -> Bool {
        guard let arguments = node.arguments,
              case .argumentList(let argList) = arguments else {
            return false
        }

        var hasError = false

        for argument in argList {
            guard let label = argument.label?.text else {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(argument),
                        message: MockableError.invalidMacroArgument("@Mockable does not accept unlabeled arguments")
                    )
                )
                hasError = true
                continue
            }

            context.diagnose(
                Diagnostic(
                    node: Syntax(argument),
                    message: MockableError.invalidMacroArgument(
                        "unexpected argument label '\(label)'; @Mockable does not accept arguments"
                    )
                )
            )
            hasError = true
        }

        return hasError
    }

    private static func diagnoseUnsupportedMembers(
        in members: MemberBlockItemListSyntax,
        context: some MacroExpansionContext
    ) -> Bool {
        var hasError = false

        for member in members {
            if let ifConfigDecl = member.decl.as(IfConfigDeclSyntax.self) {
                if diagnoseUnsupportedMembers(in: ifConfigDecl, context: context) {
                    hasError = true
                }
                continue
            }

            // Generated mock members evaluate @autoclosure arguments to record them,
            // so an autoclosure's own effects must be covered by the requirement.
            if let functionDecl = member.decl.as(FunctionDeclSyntax.self) {
                let effects = functionDecl.signature.effectSpecifiers
                if diagnoseAutoclosureParameters(
                    functionDecl.signature.parameterClause.parameters,
                    coversThrows: effects?.hasThrowsEffect ?? false,
                    coversAsync: effects?.asyncSpecifier != nil,
                    inSubscript: false,
                    context: context
                ) {
                    hasError = true
                    continue
                }
            }

            if let subscriptDecl = member.decl.as(SubscriptDeclSyntax.self) {
                if diagnoseAutoclosureParameters(
                    subscriptDecl.parameterClause.parameters,
                    coversThrows: false,
                    coversAsync: false,
                    inSubscript: true,
                    context: context
                ) {
                    hasError = true
                    continue
                }
            }

            // Initializer witnesses evaluate @autoclosure arguments to record them, so an
            // autoclosure's own effects must be covered by the requirement, as for methods.
            if let initDecl = member.decl.as(InitializerDeclSyntax.self) {
                let effects = initDecl.signature.effectSpecifiers
                if diagnoseAutoclosureParameters(
                    initDecl.signature.parameterClause.parameters,
                    coversThrows: effects?.hasThrowsEffect ?? false,
                    coversAsync: effects?.asyncSpecifier != nil,
                    inSubscript: false,
                    context: context
                ) {
                    hasError = true
                    continue
                }
            }

            if memberIsSupported(member.decl) {
                continue
            }

            context.diagnose(
                Diagnostic(node: Syntax(member.decl), message: MockableError.unsupportedMember(member.decl.trimmedDescription))
            )
            hasError = true
        }

        return hasError
    }

    /// Diagnoses `@autoclosure` parameters whose own effects (`throws`/`async`)
    /// are not covered by the enclosing requirement. The generated mock evaluates
    /// autoclosure arguments once per call to record them, which is only possible
    /// when the surrounding member can apply `try`/`await`.
    private static func diagnoseAutoclosureParameters(
        _ parameters: FunctionParameterListSyntax,
        coversThrows: Bool,
        coversAsync: Bool,
        inSubscript: Bool,
        context: some MacroExpansionContext
    ) -> Bool {
        var hasError = false

        for param in parameters {
            guard let functionType = MockGenerator.autoclosureFunctionType(of: param) else {
                continue
            }
            let isThrowing = functionType.effectSpecifiers?.hasThrowsEffect ?? false
            let isAsync = functionType.effectSpecifiers?.asyncSpecifier != nil

            var uncoveredEffects: [String] = []
            if isThrowing && !coversThrows {
                uncoveredEffects.append("throws")
            }
            if isAsync && !coversAsync {
                uncoveredEffects.append("async")
            }
            guard !uncoveredEffects.isEmpty else {
                continue
            }

            let name = (param.secondName ?? param.firstName).text
            let message: String
            if inSubscript {
                message = "Cannot mock @autoclosure parameter '\(name)': effectful autoclosures are not supported in subscript requirements"
            } else {
                let effects = uncoveredEffects.joined(separator: "' and '")
                message = "Cannot mock @autoclosure parameter '\(name)': the mock evaluates autoclosure arguments when called, so the requirement must be declared '\(effects)'"
            }
            context.diagnose(
                Diagnostic(node: Syntax(param), message: MockableError.unsupportedAutoclosureEffect(message))
            )
            hasError = true
        }

        return hasError
    }

    /// Diagnoses `init` requirements that appear in a context the macro cannot yet mock.
    /// When `isUnsupportedContext` is `false` (a plain, non-inheriting protocol) no
    /// diagnostics are emitted and initializers are generated normally.
    private static func diagnoseInitializerContext(
        in members: MemberBlockItemListSyntax,
        isUnsupportedContext: Bool,
        context: some MacroExpansionContext
    ) -> Bool {
        guard isUnsupportedContext else {
            return false
        }

        var hasError = false

        for member in members {
            if let ifConfigDecl = member.decl.as(IfConfigDeclSyntax.self) {
                for clause in ifConfigDecl.clauses {
                    guard let elements = clause.elements,
                          case .decls(let decls) = elements else {
                        continue
                    }
                    if diagnoseInitializerContext(in: decls, isUnsupportedContext: true, context: context) {
                        hasError = true
                    }
                }
                continue
            }

            if member.decl.is(InitializerDeclSyntax.self) {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(member.decl),
                        message: MockableError.unsupportedInitializer(
                            "init requirements declared on an inheriting protocol are not yet supported"
                        )
                    )
                )
                hasError = true
            }
        }

        return hasError
    }

    private static func diagnoseUnsupportedMembers(
        in ifConfigDecl: IfConfigDeclSyntax,
        context: some MacroExpansionContext
    ) -> Bool {
        var hasError = false

        for clause in ifConfigDecl.clauses {
            guard let elements = clause.elements,
                  case .decls(let members) = elements else {
                continue
            }

            if diagnoseUnsupportedMembers(in: members, context: context) {
                hasError = true
            }
        }

        return hasError
    }

    private static func memberIsSupported(_ decl: DeclSyntax) -> Bool {
        if decl.is(InitializerDeclSyntax.self) {
            return true
        }

        if decl.is(AssociatedTypeDeclSyntax.self) {
            return true
        }

        if decl.is(TypeAliasDeclSyntax.self) {
            return true
        }

        if decl.is(FunctionDeclSyntax.self) {
            return true
        }

        if decl.is(VariableDeclSyntax.self) {
            return true
        }

        if let subscriptDecl = decl.as(SubscriptDeclSyntax.self) {
            return !hasTypeMemberModifier(subscriptDecl.modifiers)
        }

        return false
    }

    private static func hasTypeMemberModifier(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { modifier in
            let modifierName = modifier.name.text
            return modifierName == "static" || modifierName == "class"
        }
    }
}
