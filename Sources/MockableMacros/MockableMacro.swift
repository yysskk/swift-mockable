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

        let hasInvalidArguments = diagnoseArguments(from: node, in: context)
        let hasUnsupportedMembers = diagnoseUnsupportedMembers(in: protocolDecl.memberBlock.members, context: context)
        guard !hasInvalidArguments, !hasUnsupportedMembers else {
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
