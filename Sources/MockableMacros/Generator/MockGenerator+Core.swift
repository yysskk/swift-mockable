import SwiftSyntax
import SwiftSyntaxBuilder

struct MockGenerator {
    let protocolName: String
    let mockClassName: String
    let members: MemberBlockItemListSyntax
    let isSendable: Bool
    let isActor: Bool
    let accessLevel: AccessLevel
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
            return DeclSyntax(try generateActorMock())
        }

        if isSendable {
            return DeclSyntax(try generateClassMock())
        }

        return DeclSyntax(try generateClassMock())
    }

    private func generateClassMock() throws -> ClassDeclSyntax {
        var classMembers: [MemberBlockItemSyntax] = []
        let needsStaticStorage = hasTypeMembers()

        classMembers.append(contentsOf: generateAssociatedTypeMembers())

        if usesInstanceStorageLock {
            let storageStruct = generateStorageStruct()
            classMembers.append(MemberBlockItemSyntax(decl: storageStruct))

            let mutexProperty = generateLockProperty()
            classMembers.append(MemberBlockItemSyntax(decl: mutexProperty))
        }

        if needsStaticStorage {
            let staticStorageStruct = generateStaticStorageStruct()
            classMembers.append(MemberBlockItemSyntax(decl: staticStorageStruct))

            let staticMutexProperty = generateLockProperty(
                propertyName: "_staticStorage",
                storageTypeName: "StaticStorage",
                isStatic: true
            )
            classMembers.append(MemberBlockItemSyntax(decl: staticMutexProperty))
        }

        classMembers.append(contentsOf: generateMockMembers())

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

        return ClassDeclSyntax(
            attributes: AttributeListSyntax([]),
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

        actorMembers.append(contentsOf: generateAssociatedTypeMembers())

        let storageStruct = generateStorageStruct()
        actorMembers.append(MemberBlockItemSyntax(decl: storageStruct))

        let mutexProperty = generateLockProperty()
        actorMembers.append(MemberBlockItemSyntax(decl: mutexProperty))

        if hasTypeMembers() {
            let staticStorageStruct = generateStaticStorageStruct()
            actorMembers.append(MemberBlockItemSyntax(decl: staticStorageStruct))

            let staticMutexProperty = generateLockProperty(
                propertyName: "_staticStorage",
                storageTypeName: "StaticStorage",
                isStatic: true
            )
            actorMembers.append(MemberBlockItemSyntax(decl: staticMutexProperty))
        }

        actorMembers.append(contentsOf: generateMockMembers())

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

        return ActorDeclSyntax(
            attributes: AttributeListSyntax([]),
            modifiers: DeclModifierListSyntax(modifiers),
            name: .identifier(mockClassName),
            inheritanceClause: InheritanceClauseSyntax(
                inheritedTypes: InheritedTypeListSyntax(inheritedTypes)
            ),
            memberBlock: memberBlock
        )
    }

    private func generateMockMembers() -> [MemberBlockItemSyntax] {
        let methodGroups = groupMethodsByNameIncludingConditional()

        return mapMemberBlockItemsPreservingIfConfig { decl in
            if let funcDecl = decl.as(FunctionDeclSyntax.self) {
                let funcName = funcDecl.name.text
                let methodGroup = methodGroups[funcName] ?? []
                let isOverloaded = methodGroup.count > 1
                let suffix = isOverloaded ? Self.functionIdentifierSuffix(from: funcDecl, in: methodGroup) : ""
                return generateFunctionMock(funcDecl, suffix: suffix)
            }

            if let varDecl = decl.as(VariableDeclSyntax.self) {
                return generateVariableMock(varDecl)
            }

            if let subscriptDecl = decl.as(SubscriptDeclSyntax.self) {
                return generateSubscriptMock(subscriptDecl)
            }

            return []
        }
    }

}
