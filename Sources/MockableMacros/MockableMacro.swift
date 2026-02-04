import SwiftCompilerPlugin
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
            throw MockableError.notAProtocol
        }

        // Parse legacyLock parameter from macro arguments
        let forceLegacyLock = parseLegacyLockArgument(from: node)

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

        let members = protocolDecl.memberBlock.members

        // Extract associated type declarations
        var associatedTypes: [AssociatedTypeDeclSyntax] = []
        for member in members {
            if let associatedTypeDecl = member.decl.as(AssociatedTypeDeclSyntax.self) {
                associatedTypes.append(associatedTypeDecl)
            }
        }

        // Extract access level from the protocol declaration
        let accessLevel = AccessLevel.from(protocolDecl: protocolDecl)

        let generator = MockGenerator(
            protocolName: protocolName,
            mockClassName: mockClassName,
            members: members,
            associatedTypes: associatedTypes,
            isSendable: isSendable || hasSendableAttribute,
            isActor: isActor,
            accessLevel: accessLevel,
            forceLegacyLock: forceLegacyLock
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

    /// Parses the `legacyLock` argument from the macro attribute.
    private static func parseLegacyLockArgument(from node: AttributeSyntax) -> Bool {
        guard let arguments = node.arguments,
              case .argumentList(let argList) = arguments else {
            return false
        }

        for argument in argList {
            if argument.label?.text == "legacyLock",
               let boolExpr = argument.expression.as(BooleanLiteralExprSyntax.self) {
                return boolExpr.literal.tokenKind == .keyword(.true)
            }
        }

        return false
    }
}
