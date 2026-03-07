import SwiftSyntax
import SwiftSyntaxBuilder

struct MockGenerator {
    let protocolName: String
    let mockClassName: String
    let members: MemberBlockItemListSyntax
    let isSendable: Bool
    let isActor: Bool
    let accessLevel: AccessLevel
    let forceLegacyLock: Bool
    let parentMockClassName: String?

    var hasParentMock: Bool {
        parentMockClassName != nil && !isActor
    }

    /// Builds a DeclModifierListSyntax with the appropriate access level modifier for members.
    /// For `private` protocols, members use `fileprivate` to satisfy protocol requirements.
    func buildModifiers(additional: [DeclModifierSyntax] = []) -> DeclModifierListSyntax {
        var modifiers: [DeclModifierSyntax] = []
        if let accessModifier = accessLevel.makeMemberModifier() {
            modifiers.append(accessModifier)
        }
        modifiers.append(contentsOf: additional)
        return DeclModifierListSyntax(modifiers)
    }

    /// Builds a DeclModifierListSyntax for the class/actor declaration itself.
    func buildClassModifiers(additional: [DeclModifierSyntax] = []) -> DeclModifierListSyntax {
        var modifiers: [DeclModifierSyntax] = []
        if let accessModifier = accessLevel.makeModifier() {
            modifiers.append(accessModifier)
        }
        modifiers.append(contentsOf: additional)
        return DeclModifierListSyntax(modifiers)
    }

    func generate() throws -> DeclSyntax {
        if isActor {
            if forceLegacyLock {
                return DeclSyntax(try generateActorMock(storageStrategy: .legacyLock))
            }
            return DeclSyntax(try generateActorMockWithBackwardCompatibility())
        }

        if isSendable {
            if forceLegacyLock {
                return DeclSyntax(try generateClassMock(storageStrategy: .legacyLock))
            }
            return DeclSyntax(try generateSendableClassMockWithBackwardCompatibility())
        }

        return DeclSyntax(try generateClassMock(storageStrategy: .direct))
    }

    private func generateSendableClassMockWithBackwardCompatibility() throws -> IfConfigDeclSyntax {
        let iOS18PlusMock = try generateClassMock(storageStrategy: .mutex)
        let legacyMock = try generateClassMock(storageStrategy: .legacyLock)

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
        let iOS18PlusMock = try generateActorMock(storageStrategy: .mutex)
        let legacyMock = try generateActorMock(storageStrategy: .legacyLock)

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

    private func generateClassMock(storageStrategy: StorageStrategy) throws -> ClassDeclSyntax {
        var classMembers: [MemberBlockItemSyntax] = []

        classMembers.append(contentsOf: generateAssociatedTypeMembers())

        if storageStrategy.isLockBased {
            let storageStruct = generateStorageStruct()
            classMembers.append(MemberBlockItemSyntax(decl: storageStruct))

            let mutexProperty = generateMutexProperty(storageStrategy: storageStrategy)
            classMembers.append(MemberBlockItemSyntax(decl: mutexProperty))
        }

        classMembers.append(contentsOf: generateMockMembers(storageStrategy: storageStrategy))

        let resetMethod = generateResetMethod()
        classMembers.append(MemberBlockItemSyntax(decl: resetMethod))

        let memberBlock = MemberBlockSyntax(
            leftBrace: .leftBraceToken(trailingTrivia: .newline),
            members: MemberBlockItemListSyntax(classMembers),
            rightBrace: .rightBraceToken(leadingTrivia: .newline)
        )

        var inheritedTypes: [InheritedTypeSyntax] = []

        if hasParentMock, let parentMockClassName {
            inheritedTypes.append(
                InheritedTypeSyntax(
                    type: TypeSyntax(stringLiteral: parentMockClassName),
                    trailingComma: .commaToken()
                )
            )
        }

        inheritedTypes.append(
            InheritedTypeSyntax(type: TypeSyntax(stringLiteral: protocolName))
        )

        if isSendable {
            inheritedTypes[inheritedTypes.count - 1] = InheritedTypeSyntax(
                type: inheritedTypes[inheritedTypes.count - 1].type,
                trailingComma: .commaToken()
            )
            inheritedTypes.append(InheritedTypeSyntax(type: TypeSyntax(stringLiteral: "@unchecked Sendable")))
        }

        var modifiers: [DeclModifierSyntax] = []
        if let accessModifier = accessLevel.makeModifier() {
            modifiers.append(accessModifier)
        }

        var attributes: [AttributeListSyntax.Element] = []
        if storageStrategy == .mutex {
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

    private func generateActorMock(storageStrategy: StorageStrategy) throws -> ActorDeclSyntax {
        var actorMembers: [MemberBlockItemSyntax] = []

        actorMembers.append(contentsOf: generateAssociatedTypeMembers())

        let storageStruct = generateStorageStruct()
        actorMembers.append(MemberBlockItemSyntax(decl: storageStruct))

        let mutexProperty = generateMutexProperty(storageStrategy: storageStrategy)
        actorMembers.append(MemberBlockItemSyntax(decl: mutexProperty))

        actorMembers.append(contentsOf: generateMockMembers(storageStrategy: storageStrategy))

        let resetMethod = generateResetMethod()
        actorMembers.append(MemberBlockItemSyntax(decl: resetMethod))

        let memberBlock = MemberBlockSyntax(
            leftBrace: .leftBraceToken(trailingTrivia: .newline),
            members: MemberBlockItemListSyntax(actorMembers),
            rightBrace: .rightBraceToken(leadingTrivia: .newline)
        )

        let inheritedTypes: [InheritedTypeSyntax] = [
            InheritedTypeSyntax(type: TypeSyntax(stringLiteral: protocolName))
        ]

        var modifiers: [DeclModifierSyntax] = []
        if let accessModifier = accessLevel.makeModifier() {
            modifiers.append(accessModifier)
        }

        var attributes: [AttributeListSyntax.Element] = []
        if storageStrategy == .mutex {
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

    private func generateMockMembers(storageStrategy: StorageStrategy) -> [MemberBlockItemSyntax] {
        let methodGroups = groupMethodsByNameIncludingConditional()

        return mapMemberBlockItemsPreservingIfConfig { decl in
            if let funcDecl = decl.as(FunctionDeclSyntax.self) {
                let funcName = funcDecl.name.text
                let methodGroup = methodGroups[funcName] ?? []
                let isOverloaded = methodGroup.count > 1
                let suffix = isOverloaded ? Self.functionIdentifierSuffix(from: funcDecl, in: methodGroup) : ""
                return generateFunctionMock(funcDecl, suffix: suffix, storageStrategy: storageStrategy)
            }

            if let varDecl = decl.as(VariableDeclSyntax.self) {
                return generateVariableMock(varDecl, storageStrategy: storageStrategy)
            }

            if let subscriptDecl = decl.as(SubscriptDeclSyntax.self) {
                return generateSubscriptMock(subscriptDecl, storageStrategy: storageStrategy)
            }

            return []
        }
    }

    // MARK: - Helper Methods

    /// Groups function declarations by their name to detect overloaded methods.
    func groupMethodsByName() -> [String: [FunctionDeclSyntax]] {
        var methodGroups: [String: [FunctionDeclSyntax]] = [:]

        for member in members {
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                let funcName = funcDecl.name.text
                methodGroups[funcName, default: []].append(funcDecl)
            }
        }

        return methodGroups
    }
}
