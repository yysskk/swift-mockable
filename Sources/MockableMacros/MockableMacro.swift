import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct MockableMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let protocolDecl = declaration.as(ProtocolDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: Syntax(node), message: MockableError.notAProtocol))
            return []
        }

        let parsedArguments = parseArguments(from: node, in: context)
        let hasUnsupportedMembers = diagnoseUnsupportedMembers(in: protocolDecl.memberBlock.members, context: context)
        guard !parsedArguments.hasError, !hasUnsupportedMembers else {
            return []
        }

        let protocolName = protocolDecl.name.text
        let mockClassName = "\(protocolName)Mock"

        // Check if the protocol inherits from Sendable or has @Sendable attribute
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
        let parentMockClassName: String? = parentProtocolNames.first.map { "\($0)Mock" }

        let members = protocolDecl.memberBlock.members

        // Extract access level from the protocol declaration
        let accessLevel = AccessLevel.from(protocolDecl: protocolDecl)

        let generator = MockGenerator(
            protocolName: protocolName,
            mockClassName: mockClassName,
            members: members,
            isSendable: isSendable || hasSendableAttribute,
            isActor: isActor,
            accessLevel: accessLevel,
            forceLegacyLock: parsedArguments.forceLegacyLock,
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

    private struct ParsedArguments {
        var forceLegacyLock = false
        var hasError = false
    }

    /// Parses and validates `@Mockable` arguments.
    private static func parseArguments(
        from node: AttributeSyntax,
        in context: some MacroExpansionContext
    ) -> ParsedArguments {
        var parsedArguments = ParsedArguments()

        guard let arguments = node.arguments,
              case .argumentList(let argList) = arguments else {
            return parsedArguments
        }

        var seenLabels: Set<String> = []

        for argument in argList {
            guard let label = argument.label?.text else {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(argument),
                        message: MockableError.invalidMacroArgument("unlabeled arguments are not supported")
                    )
                )
                parsedArguments.hasError = true
                continue
            }

            guard seenLabels.insert(label).inserted else {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(argument),
                        message: MockableError.invalidMacroArgument("duplicate argument '\(label)'")
                    )
                )
                parsedArguments.hasError = true
                continue
            }

            switch label {
            case "legacyLock":
                guard let boolExpr = argument.expression.as(BooleanLiteralExprSyntax.self) else {
                    context.diagnose(
                        Diagnostic(
                            node: Syntax(argument),
                            message: MockableError.invalidMacroArgument("'legacyLock' must be a boolean literal")
                        )
                    )
                    parsedArguments.hasError = true
                    continue
                }

                parsedArguments.forceLegacyLock = boolExpr.literal.tokenKind == .keyword(.true)

            default:
                context.diagnose(
                    Diagnostic(
                        node: Syntax(argument),
                        message: MockableError.invalidMacroArgument(
                            "unexpected argument label '\(label)'; supported arguments: legacyLock"
                        )
                    )
                )
                parsedArguments.hasError = true
            }
        }

        return parsedArguments
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
        if decl.is(AssociatedTypeDeclSyntax.self) {
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
