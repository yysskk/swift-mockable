import SwiftSyntax
import SwiftSyntaxBuilder

struct MockGenerator {
    let protocolName: String
    let mockClassName: String
    let members: MemberBlockItemListSyntax
    let isSendable: Bool
    let isActor: Bool

    func generate() throws -> DeclSyntax {
        if isActor {
            return DeclSyntax(try generateActorMock())
        } else {
            return DeclSyntax(try generateClassMock())
        }
    }

    private func generateClassMock() throws -> ClassDeclSyntax {
        var classMembers: [MemberBlockItemSyntax] = []

        // For Sendable protocols, add a Mutex for thread-safe storage
        if isSendable {
            let storageStruct = generateStorageStruct()
            classMembers.append(MemberBlockItemSyntax(decl: storageStruct))

            let mutexProperty = generateMutexProperty()
            classMembers.append(MemberBlockItemSyntax(decl: mutexProperty))
        }

        // Generate members for each protocol requirement
        for member in members {
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                let funcMembers = generateFunctionMock(funcDecl)
                classMembers.append(contentsOf: funcMembers)
            } else if let varDecl = member.decl.as(VariableDeclSyntax.self) {
                let varMembers = generateVariableMock(varDecl)
                classMembers.append(contentsOf: varMembers)
            }
        }

        let memberBlock = MemberBlockSyntax(
            leftBrace: .leftBraceToken(trailingTrivia: .newline),
            members: MemberBlockItemListSyntax(classMembers),
            rightBrace: .rightBraceToken(leadingTrivia: .newline)
        )

        // Build inheritance clause
        var inheritedTypes: [InheritedTypeSyntax] = [
            InheritedTypeSyntax(type: TypeSyntax(stringLiteral: protocolName))
        ]
        if isSendable {
            inheritedTypes[0] = InheritedTypeSyntax(
                type: TypeSyntax(stringLiteral: protocolName),
                trailingComma: .commaToken()
            )
            inheritedTypes.append(InheritedTypeSyntax(type: TypeSyntax(stringLiteral: "Sendable")))
        }

        // Build modifiers
        var modifiers: [DeclModifierSyntax] = [
            DeclModifierSyntax(name: .keyword(.public))
        ]
        if isSendable {
            modifiers.append(DeclModifierSyntax(name: .keyword(.final)))
        }

        // Build attributes
        var attributes: [AttributeListSyntax.Element] = []
        if isSendable {
            // Add @available attribute for Mutex which requires macOS 15.0+
            var availableAttribute: AttributeSyntax = "@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)"
            availableAttribute.trailingTrivia = .newline
            attributes.append(.attribute(availableAttribute))
        }

        return ClassDeclSyntax(
            attributes: AttributeListSyntax(attributes),
            modifiers: DeclModifierListSyntax(modifiers),
            name: .identifier(mockClassName),
            inheritanceClause: InheritanceClauseSyntax(
                inheritedTypes: InheritedTypeListSyntax(inheritedTypes)
            ),
            memberBlock: memberBlock
        )
    }

    private func generateActorMock() throws -> ActorDeclSyntax {
        var actorMembers: [MemberBlockItemSyntax] = []

        // Add Storage struct and Mutex for thread-safe access (same as Sendable pattern)
        let storageStruct = generateStorageStruct()
        actorMembers.append(MemberBlockItemSyntax(decl: storageStruct))

        let mutexProperty = generateMutexProperty()
        actorMembers.append(MemberBlockItemSyntax(decl: mutexProperty))

        // Generate members for each protocol requirement using Sendable pattern
        for member in members {
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                let funcMembers = generateActorFunctionMock(funcDecl)
                actorMembers.append(contentsOf: funcMembers)
            } else if let varDecl = member.decl.as(VariableDeclSyntax.self) {
                let varMembers = generateActorVariableMock(varDecl)
                actorMembers.append(contentsOf: varMembers)
            }
        }

        let memberBlock = MemberBlockSyntax(
            leftBrace: .leftBraceToken(trailingTrivia: .newline),
            members: MemberBlockItemListSyntax(actorMembers),
            rightBrace: .rightBraceToken(leadingTrivia: .newline)
        )

        // Build inheritance clause - just the protocol name for actors
        let inheritedTypes: [InheritedTypeSyntax] = [
            InheritedTypeSyntax(type: TypeSyntax(stringLiteral: protocolName))
        ]

        // Build modifiers
        let modifiers: [DeclModifierSyntax] = [
            DeclModifierSyntax(name: .keyword(.public))
        ]

        // Build attributes - add @available for Mutex
        var attributes: [AttributeListSyntax.Element] = []
        var availableAttribute: AttributeSyntax = "@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)"
        availableAttribute.trailingTrivia = .newline
        attributes.append(.attribute(availableAttribute))

        return ActorDeclSyntax(
            attributes: AttributeListSyntax(attributes),
            modifiers: DeclModifierListSyntax(modifiers),
            name: .identifier(mockClassName),
            inheritanceClause: InheritanceClauseSyntax(
                inheritedTypes: InheritedTypeListSyntax(inheritedTypes)
            ),
            memberBlock: memberBlock
        )
    }
}
