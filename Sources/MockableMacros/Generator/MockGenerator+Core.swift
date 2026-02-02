import SwiftSyntax
import SwiftSyntaxBuilder

struct MockGenerator {
    let protocolName: String
    let mockClassName: String
    let members: MemberBlockItemListSyntax
    let associatedTypes: [AssociatedTypeDeclSyntax]
    let isSendable: Bool
    let isActor: Bool

    func generate() throws -> DeclSyntax {
        if isActor {
            return DeclSyntax(try generateActorMockWithBackwardCompatibility())
        } else if isSendable {
            return DeclSyntax(try generateSendableClassMockWithBackwardCompatibility())
        } else {
            return DeclSyntax(try generateClassMock())
        }
    }

    private func generateSendableClassMockWithBackwardCompatibility() throws -> IfConfigDeclSyntax {
        // iOS 18+ version with Mutex
        let iOS18PlusMock = try generateClassMock(useLegacyLock: false)
        // iOS 17- version with LegacyLock
        let legacyMock = try generateClassMock(useLegacyLock: true)

        let canImportCondition = FunctionCallExprSyntax(
            calledExpression: DeclReferenceExprSyntax(baseName: .identifier("canImport")),
            leftParen: .leftParenToken(),
            arguments: LabeledExprListSyntax([
                LabeledExprSyntax(expression: DeclReferenceExprSyntax(baseName: .identifier("Synchronization")))
            ]),
            rightParen: .rightParenToken()
        )

        let ifClause = IfConfigClauseSyntax(
            poundKeyword: .poundIfToken(),
            condition: canImportCondition,
            elements: .decls(MemberBlockItemListSyntax([
                MemberBlockItemSyntax(decl: DeclSyntax(iOS18PlusMock))
            ]))
        )

        let elseClause = IfConfigClauseSyntax(
            poundKeyword: .poundElseToken(),
            condition: nil as ExprSyntax?,
            elements: .decls(MemberBlockItemListSyntax([
                MemberBlockItemSyntax(decl: DeclSyntax(legacyMock))
            ]))
        )

        return IfConfigDeclSyntax(
            clauses: IfConfigClauseListSyntax([ifClause, elseClause])
        )
    }

    private func generateActorMockWithBackwardCompatibility() throws -> IfConfigDeclSyntax {
        // iOS 18+ version with Mutex
        let iOS18PlusMock = try generateActorMock(useLegacyLock: false)
        // iOS 17- version with LegacyLock
        let legacyMock = try generateActorMock(useLegacyLock: true)

        let canImportCondition = FunctionCallExprSyntax(
            calledExpression: DeclReferenceExprSyntax(baseName: .identifier("canImport")),
            leftParen: .leftParenToken(),
            arguments: LabeledExprListSyntax([
                LabeledExprSyntax(expression: DeclReferenceExprSyntax(baseName: .identifier("Synchronization")))
            ]),
            rightParen: .rightParenToken()
        )

        let ifClause = IfConfigClauseSyntax(
            poundKeyword: .poundIfToken(),
            condition: canImportCondition,
            elements: .decls(MemberBlockItemListSyntax([
                MemberBlockItemSyntax(decl: DeclSyntax(iOS18PlusMock))
            ]))
        )

        let elseClause = IfConfigClauseSyntax(
            poundKeyword: .poundElseToken(),
            condition: nil as ExprSyntax?,
            elements: .decls(MemberBlockItemListSyntax([
                MemberBlockItemSyntax(decl: DeclSyntax(legacyMock))
            ]))
        )

        return IfConfigDeclSyntax(
            clauses: IfConfigClauseListSyntax([ifClause, elseClause])
        )
    }

    private func generateClassMock(useLegacyLock: Bool = false) throws -> ClassDeclSyntax {
        var classMembers: [MemberBlockItemSyntax] = []

        // Generate typealiases for associated types
        for associatedType in associatedTypes {
            let typealiasDecl = generateTypeAlias(for: associatedType)
            classMembers.append(MemberBlockItemSyntax(decl: typealiasDecl))
        }

        // For Sendable protocols, add a lock for thread-safe storage
        if isSendable {
            let storageStruct = generateStorageStruct()
            classMembers.append(MemberBlockItemSyntax(decl: storageStruct))

            let mutexProperty = generateMutexProperty(useLegacyLock: useLegacyLock)
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
            } else if let subscriptDecl = member.decl.as(SubscriptDeclSyntax.self) {
                let subscriptMembers = generateSubscriptMock(subscriptDecl)
                classMembers.append(contentsOf: subscriptMembers)
            }
        }

        // Generate reset method
        let resetMethod = generateResetMethod()
        classMembers.append(MemberBlockItemSyntax(decl: resetMethod))

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
        // Only add @available attribute for Mutex (iOS 18+), not for LegacyLock
        if isSendable && !useLegacyLock {
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

    private func generateActorMock(useLegacyLock: Bool = false) throws -> ActorDeclSyntax {
        var actorMembers: [MemberBlockItemSyntax] = []

        // Generate typealiases for associated types
        for associatedType in associatedTypes {
            let typealiasDecl = generateTypeAlias(for: associatedType)
            actorMembers.append(MemberBlockItemSyntax(decl: typealiasDecl))
        }

        // Add Storage struct and lock for thread-safe access (same as Sendable pattern)
        let storageStruct = generateStorageStruct()
        actorMembers.append(MemberBlockItemSyntax(decl: storageStruct))

        let mutexProperty = generateMutexProperty(useLegacyLock: useLegacyLock)
        actorMembers.append(MemberBlockItemSyntax(decl: mutexProperty))

        // Generate members for each protocol requirement using Sendable pattern
        for member in members {
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                let funcMembers = generateActorFunctionMock(funcDecl)
                actorMembers.append(contentsOf: funcMembers)
            } else if let varDecl = member.decl.as(VariableDeclSyntax.self) {
                let varMembers = generateActorVariableMock(varDecl)
                actorMembers.append(contentsOf: varMembers)
            } else if let subscriptDecl = member.decl.as(SubscriptDeclSyntax.self) {
                let subscriptMembers = generateActorSubscriptMock(subscriptDecl)
                actorMembers.append(contentsOf: subscriptMembers)
            }
        }

        // Generate reset method
        let resetMethod = generateResetMethod()
        actorMembers.append(MemberBlockItemSyntax(decl: resetMethod))

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

        // Build attributes - only add @available for Mutex (iOS 18+), not for LegacyLock
        var attributes: [AttributeListSyntax.Element] = []
        if !useLegacyLock {
            var availableAttribute: AttributeSyntax = "@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)"
            availableAttribute.trailingTrivia = .newline
            attributes.append(.attribute(availableAttribute))
        }

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
