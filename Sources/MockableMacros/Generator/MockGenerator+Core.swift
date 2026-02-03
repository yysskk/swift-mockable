import SwiftSyntax
import SwiftSyntaxBuilder

struct MockGenerator {
    let protocolName: String
    let mockClassName: String
    let members: MemberBlockItemListSyntax
    let associatedTypes: [AssociatedTypeDeclSyntax]
    let isSendable: Bool
    let isActor: Bool
    let accessLevel: AccessLevel
    let forceLegacyLock: Bool

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
                // Force LegacyLock only (no #if canImport)
                return DeclSyntax(try generateActorMock(useLegacyLock: true))
            }
            return DeclSyntax(try generateActorMockWithBackwardCompatibility())
        } else if isSendable {
            if forceLegacyLock {
                // Force LegacyLock only (no #if canImport)
                return DeclSyntax(try generateClassMock(useLegacyLock: true))
            }
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

        // Group methods by name to detect overloads (including conditional members)
        let methodGroups = groupMethodsByNameIncludingConditional()

        // Extract all members including those in #if blocks
        let conditionalMembers = extractConditionalMembers()

        // Group members by their condition
        var unconditionalMembers: [MemberBlockItemSyntax] = []
        var membersByCondition: [String: [MemberBlockItemSyntax]] = [:]
        var conditionExprs: [String: ExprSyntax] = [:]

        // Generate members for each protocol requirement
        for conditionalMember in conditionalMembers {
            var generatedMembers: [MemberBlockItemSyntax] = []

            if let funcDecl = conditionalMember.decl.as(FunctionDeclSyntax.self) {
                let funcName = funcDecl.name.text
                let methodGroup = methodGroups[funcName] ?? []
                let isOverloaded = methodGroup.count > 1
                let suffix = isOverloaded ? Self.functionIdentifierSuffix(from: funcDecl, in: methodGroup) : ""
                let funcMembers = generateFunctionMock(funcDecl, suffix: suffix)
                generatedMembers.append(contentsOf: funcMembers)
            } else if let varDecl = conditionalMember.decl.as(VariableDeclSyntax.self) {
                let varMembers = generateVariableMock(varDecl)
                generatedMembers.append(contentsOf: varMembers)
            } else if let subscriptDecl = conditionalMember.decl.as(SubscriptDeclSyntax.self) {
                let subscriptMembers = generateSubscriptMock(subscriptDecl)
                generatedMembers.append(contentsOf: subscriptMembers)
            }

            if let condition = conditionalMember.condition {
                let conditionKey = condition.trimmedDescription
                conditionExprs[conditionKey] = condition
                membersByCondition[conditionKey, default: []].append(contentsOf: generatedMembers)
            } else {
                unconditionalMembers.append(contentsOf: generatedMembers)
            }
        }

        // Add unconditional members first
        classMembers.append(contentsOf: unconditionalMembers)

        // Add conditional members wrapped in their respective #if blocks (sorted for deterministic output)
        for conditionKey in membersByCondition.keys.sorted() {
            guard let members = membersByCondition[conditionKey],
                  let condition = conditionExprs[conditionKey] else {
                continue
            }
            let wrappedMember = Self.wrapInIfConfig(members: members, condition: condition)
            classMembers.append(wrappedMember)
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
        var modifiers: [DeclModifierSyntax] = []
        if let accessModifier = accessLevel.makeModifier() {
            modifiers.append(accessModifier)
        }
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

        // Group methods by name to detect overloads (including conditional members)
        let methodGroups = groupMethodsByNameIncludingConditional()

        // Extract all members including those in #if blocks
        let conditionalMembers = extractConditionalMembers()

        // Group members by their condition
        var unconditionalMembers: [MemberBlockItemSyntax] = []
        var membersByCondition: [String: [MemberBlockItemSyntax]] = [:]
        var conditionExprs: [String: ExprSyntax] = [:]

        // Generate members for each protocol requirement using Sendable pattern
        for conditionalMember in conditionalMembers {
            var generatedMembers: [MemberBlockItemSyntax] = []

            if let funcDecl = conditionalMember.decl.as(FunctionDeclSyntax.self) {
                let funcName = funcDecl.name.text
                let methodGroup = methodGroups[funcName] ?? []
                let isOverloaded = methodGroup.count > 1
                let suffix = isOverloaded ? Self.functionIdentifierSuffix(from: funcDecl, in: methodGroup) : ""
                let funcMembers = generateActorFunctionMock(funcDecl, suffix: suffix)
                generatedMembers.append(contentsOf: funcMembers)
            } else if let varDecl = conditionalMember.decl.as(VariableDeclSyntax.self) {
                let varMembers = generateActorVariableMock(varDecl)
                generatedMembers.append(contentsOf: varMembers)
            } else if let subscriptDecl = conditionalMember.decl.as(SubscriptDeclSyntax.self) {
                let subscriptMembers = generateActorSubscriptMock(subscriptDecl)
                generatedMembers.append(contentsOf: subscriptMembers)
            }

            if let condition = conditionalMember.condition {
                let conditionKey = condition.trimmedDescription
                conditionExprs[conditionKey] = condition
                membersByCondition[conditionKey, default: []].append(contentsOf: generatedMembers)
            } else {
                unconditionalMembers.append(contentsOf: generatedMembers)
            }
        }

        // Add unconditional members first
        actorMembers.append(contentsOf: unconditionalMembers)

        // Add conditional members wrapped in their respective #if blocks (sorted for deterministic output)
        for conditionKey in membersByCondition.keys.sorted() {
            guard let members = membersByCondition[conditionKey],
                  let condition = conditionExprs[conditionKey] else {
                continue
            }
            let wrappedMember = Self.wrapInIfConfig(members: members, condition: condition)
            actorMembers.append(wrappedMember)
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
        var modifiers: [DeclModifierSyntax] = []
        if let accessModifier = accessLevel.makeModifier() {
            modifiers.append(accessModifier)
        }

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
