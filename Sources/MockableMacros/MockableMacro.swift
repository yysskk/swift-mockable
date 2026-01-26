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

        let generator = MockGenerator(
            protocolName: protocolName,
            mockClassName: mockClassName,
            members: members,
            associatedTypes: associatedTypes,
            isSendable: isSendable || hasSendableAttribute,
            isActor: isActor
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
}
