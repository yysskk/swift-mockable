import SwiftSyntax
import SwiftSyntaxBuilder

/// Builds the mock type for a single `@Mockable` protocol from its parsed shape.
///
/// `MockableMacro` extracts the protocol's name, members, conformances, and access level
/// into a `MockGenerator`, then calls ``generate()``. The generator's responsibilities are
/// split across `MockGenerator+*.swift` extensions by concern: `+Function`, `+Variable`,
/// and `+Subscript` emit the per-requirement witnesses and their tracking members;
/// `+Storage` builds the lock-backed storage structs used for `Sendable`/actor mocks;
/// `+Reset` emits `resetMock()`; and `+Helpers` holds the shared type-erasure and naming
/// utilities.
struct MockGenerator {
    let protocolName: String
    let mockClassName: String
    let members: MemberBlockItemListSyntax
    let isSendable: Bool
    let isActor: Bool
    let isMainActor: Bool
    let accessLevel: AccessLevel
    let parentMockClassName: String?

    var hasParentMock: Bool {
        parentMockClassName != nil && !isActor
    }

    /// Builds a DeclModifierListSyntax with the appropriate access level modifier for members.
    /// For `private` protocols, members use `fileprivate` to satisfy protocol requirements.
    func buildModifiers(
        additional: [DeclModifierSyntax] = [],
        isOverridable: Bool = false
    ) -> DeclModifierListSyntax {
        var modifiers: [DeclModifierSyntax] = []
        if let accessModifier = accessLevel.makeMemberModifier(isOverridable: isOverridable) {
            modifiers.append(accessModifier)
        }
        modifiers.append(contentsOf: additional)
        return DeclModifierListSyntax(modifiers)
    }

    /// Builds a DeclModifierListSyntax for the class/actor declaration itself.
    func buildClassModifiers(
        additional: [DeclModifierSyntax] = [],
        supportsOpen: Bool = false
    ) -> DeclModifierListSyntax {
        var modifiers: [DeclModifierSyntax] = []
        if let accessModifier = accessLevel.makeModifier(supportsOpen: supportsOpen) {
            modifiers.append(accessModifier)
        }
        modifiers.append(contentsOf: additional)
        return DeclModifierListSyntax(modifiers)
    }

    var canBeSubclassedOutsideModule: Bool {
        accessLevel == .public && !isActor
    }

    /// Builds the mock declaration: an `actor` for `Actor` protocols, otherwise a `class`.
    /// `Sendable` and non-`Sendable` class mocks share the same builder; they differ only
    /// in whether members are lock-backed, which the builder decides per member.
    func generate() -> DeclSyntax {
        if isActor {
            return DeclSyntax(generateActorMock())
        }

        return DeclSyntax(generateClassMock())
    }

    /// Builds the members shared by class and actor mocks, in emission order:
    /// associated-type aliases, lock-backed storage (instance, then static), an
    /// explicit initializer where the access level requires one, the per-requirement
    /// mock members, and `resetMock()`. Instance lock storage is emitted for every
    /// actor mock and for `Sendable` class mocks (`usesInstanceStorageLock` covers both).
    private func buildMockMemberBlock() -> MemberBlockSyntax {
        var members: [MemberBlockItemSyntax] = []

        members.append(contentsOf: generateAssociatedTypeMembers())

        if usesInstanceStorageLock {
            let storageStruct = generateStorageStruct()
            members.append(MemberBlockItemSyntax(decl: storageStruct))

            let mutexProperty = generateLockProperty()
            members.append(MemberBlockItemSyntax(decl: mutexProperty))
        }

        if hasTypeMembers() {
            let staticStorageStruct = generateStaticStorageStruct()
            members.append(MemberBlockItemSyntax(decl: staticStorageStruct))

            let staticMutexProperty = generateLockProperty(
                propertyName: MockNaming.staticStorageName,
                storageTypeName: MockNaming.staticStorageTypeName,
                isStatic: true
            )
            members.append(MemberBlockItemSyntax(decl: staticMutexProperty))
        }

        // Generate explicit init when access level requires it (e.g., public/package)
        // Without this, the default init is internal, making the mock unusable across modules.
        // Skipped when:
        // - the protocol declares its own `init` requirements: those generate `required init`
        //   witnesses that already provide accessible initializers; or
        // - the mock subclasses a parent mock: it inherits the parent's initializers, so
        //   synthesizing its own would shadow an inherited `required init` and break protocols
        //   whose parent declares an `init` requirement. (An actor mock never has a parent.)
        if (accessLevel == .public || accessLevel == .package) && !hasInitializerRequirements && !hasParentMock {
            let initDecl = generateInit()
            members.append(MemberBlockItemSyntax(decl: initDecl))
        }

        members.append(contentsOf: generateMockMembers())

        let resetMethod = generateResetMethod()
        members.append(MemberBlockItemSyntax(decl: resetMethod))

        return MemberBlockSyntax(
            leftBrace: .leftBraceToken(trailingTrivia: .newline),
            members: MemberBlockItemListSyntax(members),
            rightBrace: .rightBraceToken(leadingTrivia: .newline)
        )
    }

    private func generateClassMock() -> ClassDeclSyntax {
        let memberBlock = buildMockMemberBlock()

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

        var classAttributes: [AttributeListSyntax.Element] = []
        if isMainActor {
            classAttributes.append(.attribute(
                AttributeSyntax(attributeName: IdentifierTypeSyntax(name: .identifier("MainActor")))
            ))
        }

        return ClassDeclSyntax(
            attributes: AttributeListSyntax(classAttributes),
            modifiers: buildClassModifiers(supportsOpen: true),
            name: .identifier(mockClassName),
            inheritanceClause: InheritanceClauseSyntax(
                inheritedTypes: InheritedTypeListSyntax(inheritedTypes)
            ),
            memberBlock: memberBlock
        )
    }

    private func generateActorMock() -> ActorDeclSyntax {
        let memberBlock = buildMockMemberBlock()

        let inheritedTypes: [InheritedTypeSyntax] = [
            InheritedTypeSyntax(type: TypeSyntax(stringLiteral: protocolName))
        ]

        return ActorDeclSyntax(
            attributes: AttributeListSyntax([]),
            modifiers: buildClassModifiers(),
            name: .identifier(mockClassName),
            inheritanceClause: InheritanceClauseSyntax(
                inheritedTypes: InheritedTypeListSyntax(inheritedTypes)
            ),
            memberBlock: memberBlock
        )
    }

    private func generateMockMembers() -> [MemberBlockItemSyntax] {
        let overloads = makeOverloadContext()

        return mapMemberBlockItemsPreservingIfConfig { decl in
            if let initDecl = decl.as(InitializerDeclSyntax.self) {
                return generateInitializerMock(
                    initDecl,
                    requirement: initializerTrackingRequirement(for: initDecl, overloads: overloads)
                )
            }

            if let funcDecl = decl.as(FunctionDeclSyntax.self) {
                return generateFunctionMock(
                    funcDecl,
                    requirement: functionTrackingRequirement(for: funcDecl, overloads: overloads)
                )
            }

            if let varDecl = decl.as(VariableDeclSyntax.self) {
                return generateVariableMock(varDecl)
            }

            if let subscriptDecl = decl.as(SubscriptDeclSyntax.self) {
                return generateSubscriptMock(
                    subscriptDecl,
                    requirement: subscriptTrackingRequirement(for: subscriptDecl)
                )
            }

            return []
        }
    }

    /// Generates an explicit parameterless initializer for the mock class.
    /// For `public` / `package` protocols, the default synthesized initializer is `internal`,
    /// which prevents the mock from being instantiated across module boundaries. This is only
    /// emitted for root mocks; a mock that subclasses a parent mock inherits the parent's
    /// initializers instead.
    private func generateInit() -> DeclSyntax {
        let initDecl = InitializerDeclSyntax(
            modifiers: buildModifiers(isOverridable: false),
            signature: FunctionSignatureSyntax(
                parameterClause: FunctionParameterClauseSyntax(
                    parameters: FunctionParameterListSyntax([])
                )
            ),
            body: CodeBlockSyntax(
                statements: CodeBlockItemListSyntax([])
            )
        )

        return DeclSyntax(initDecl)
    }

}
