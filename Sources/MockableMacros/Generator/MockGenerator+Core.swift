import SwiftSyntax
import SwiftSyntaxBuilder

/// Builds the mock type for a single `@Mockable` protocol from its parsed shape.
///
/// `MockableMacro` extracts the protocol's shape into a `MockGenerator`, then calls
/// ``generate()``. The generator's responsibilities are split across
/// `MockGenerator+*.swift` extensions by concern:
///
/// - `Requirement` classifies each protocol member once; every pass switches over it.
/// - `TrackingModel` derives, once per requirement, which tracking slots it needs and
///   how they are named and typed. `+Function`, `+Variable`, `+Subscript`, and
///   `+Initializer` emit the witnesses and their tracking members from that model;
///   `+Storage` builds the lock-backed storage structs from it; `+Reset` emits
///   `resetMock()` from it.
/// - `TrackingAccess` expresses, once, how a witness records a call and reads a handler
///   or backing slot on each storage model, so every witness generator has one body.
/// - `+Emit` holds the shared property and statement builders those generators use.
/// - `+TypeErasure`, `+ParameterModel`, `+DefaultReturnValue`, `+OverloadSuffix`,
///   `+AccessorInspection`, and `+StorageModel` hold the shared analyses: erasing
///   generic parameters, shaping recorded arguments, choosing unset-handler defaults,
///   disambiguating overloads, reading accessor blocks, and deciding storage flavor.
/// - `+IfConfigTraversal` keeps every generator's output aligned with the protocol's
///   conditional-compilation structure.
struct MockGenerator {
    /// The protocol-level facts that drive generation: its name, conformances,
    /// isolation, access level, and parent mock.
    let shape: ProtocolShape
    /// The protocol's member block, with every requirement's parameters renamed to
    /// something the generated bodies can refer to (see `ParameterNameNormalizer`).
    let members: MemberBlockItemListSyntax
    /// Every requirement, flattened out of conditional compilation, in declaration
    /// order, for the analyses that need the whole set at once. Generation itself goes
    /// through the `map*PreservingIfConfig` drivers, which keep the `#if` structure.
    let requirements: [Requirement]
    /// The overload groups and the tracking identifiers assigned across the whole
    /// protocol, computed once so every consumer names a requirement the same way.
    let overloads: OverloadContext

    init(shape: ProtocolShape, members: MemberBlockItemListSyntax) {
        self.shape = shape
        self.members = members
        self.requirements = Requirement.all(in: members)
        self.overloads = OverloadContext(requirements: requirements)
    }

    /// Whether the protocol declares at least one `init` requirement, in which case the
    /// generated `required init` witnesses stand in for the synthesized `init()`.
    var hasInitializerRequirements: Bool {
        !overloads.initializers.isEmpty
    }

    /// The modifiers of a generated declaration: the protocol's access level as spelled
    /// for `role` (see `AccessLevel.DeclarationRole`), followed by `additional`.
    func modifiers(
        for role: AccessLevel.DeclarationRole,
        additional: [DeclModifierSyntax] = []
    ) -> DeclModifierListSyntax {
        var modifiers: [DeclModifierSyntax] = []
        if let accessModifier = shape.accessLevel.modifier(for: role) {
            modifiers.append(accessModifier)
        }
        modifiers.append(contentsOf: additional)
        return DeclModifierListSyntax(modifiers)
    }

    /// Builds the mock declaration: an `actor` for `Actor` protocols, otherwise a `class`.
    /// `Sendable` and non-`Sendable` class mocks share the same builder; they differ only
    /// in whether members are lock-backed, which the builder decides per member.
    func generate() -> DeclSyntax {
        if shape.isActor {
            return DeclSyntax(generateActorMock())
        }

        return DeclSyntax(generateClassMock())
    }

    /// Builds the members shared by class and actor mocks, in emission order:
    /// associated-type aliases, lock-backed storage (instance, then static), an
    /// explicit initializer where the access level requires one, the per-requirement
    /// mock members, the instance `resetMock()`, and the type-level `resetMock()`. Instance lock storage is emitted for every
    /// actor mock and for `Sendable` class mocks (`usesInstanceStorageLock` covers both).
    private func buildMockMemberBlock() -> MemberBlockSyntax {
        var members: [MemberBlockItemSyntax] = []

        members.append(contentsOf: generateAssociatedTypeMembers())

        if usesInstanceStorageLock {
            members.append(MemberBlockItemSyntax(decl: generateStorageStruct(for: .instance)))
            members.append(MemberBlockItemSyntax(decl: generateLockProperty(for: .instance)))
        }

        if hasTypeMembers {
            members.append(MemberBlockItemSyntax(decl: generateStorageStruct(for: .type)))
            members.append(MemberBlockItemSyntax(decl: generateLockProperty(for: .type)))
        }

        // Generate explicit init when access level requires it (e.g., public/package)
        // Without this, the default init is internal, making the mock unusable across modules.
        // Skipped when:
        // - the protocol declares its own `init` requirements: those generate `required init`
        //   witnesses that already provide accessible initializers; or
        // - the mock subclasses a parent mock: it inherits the parent's initializers, so
        //   synthesizing its own would shadow an inherited `required init` and break protocols
        //   whose parent declares an `init` requirement. (An actor mock never has a parent.)
        if (shape.accessLevel == .public || shape.accessLevel == .package) && !hasInitializerRequirements && !shape.subclassesParentMock {
            let initDecl = generateInit()
            members.append(MemberBlockItemSyntax(decl: initDecl))
        }

        members.append(contentsOf: generateMockMembers())

        members.append(MemberBlockItemSyntax(decl: generateResetMethod()))
        members.append(MemberBlockItemSyntax(decl: generateTypeResetMethod()))

        return MemberBlockSyntax(
            leftBrace: .leftBraceToken(trailingTrivia: .newline),
            members: MemberBlockItemListSyntax(members),
            rightBrace: .rightBraceToken(leadingTrivia: .newline)
        )
    }

    /// Builds the class mock: the shared member block plus the inheritance clause
    /// (parent mock first, then the protocol, then `@unchecked Sendable` when the
    /// protocol requires it) and the `@MainActor` attribute where applicable.
    private func generateClassMock() -> ClassDeclSyntax {
        let memberBlock = buildMockMemberBlock()

        var inheritedTypes: [InheritedTypeSyntax] = []

        if shape.subclassesParentMock, let parentMockClassName = shape.parentMockClassName {
            inheritedTypes.append(
                InheritedTypeSyntax(
                    type: TypeSyntax(stringLiteral: parentMockClassName),
                    trailingComma: .commaToken()
                )
            )
        }

        inheritedTypes.append(
            InheritedTypeSyntax(type: TypeSyntax(stringLiteral: shape.protocolName))
        )

        if shape.isSendable {
            inheritedTypes[inheritedTypes.count - 1] = InheritedTypeSyntax(
                type: inheritedTypes[inheritedTypes.count - 1].type,
                trailingComma: .commaToken()
            )
            inheritedTypes.append(InheritedTypeSyntax(type: TypeSyntax(stringLiteral: "@unchecked Sendable")))
        }

        var classAttributes: [AttributeListSyntax.Element] = []
        if let globalActorName = shape.globalActorName {
            classAttributes.append(.attribute(
                AttributeSyntax(attributeName: TypeSyntax(stringLiteral: globalActorName))
            ))
        }

        return ClassDeclSyntax(
            attributes: AttributeListSyntax(classAttributes),
            modifiers: modifiers(for: .subclassableMockType),
            name: .identifier(shape.mockClassName),
            inheritanceClause: InheritanceClauseSyntax(
                inheritedTypes: InheritedTypeListSyntax(inheritedTypes)
            ),
            memberBlock: memberBlock
        )
    }

    /// Builds the actor mock: the shared member block plus a conformance to the
    /// protocol alone. An actor is implicitly `Sendable` and cannot subclass, so
    /// neither the `Sendable` conformance nor a parent mock applies.
    private func generateActorMock() -> ActorDeclSyntax {
        let memberBlock = buildMockMemberBlock()

        let inheritedTypes: [InheritedTypeSyntax] = [
            InheritedTypeSyntax(type: TypeSyntax(stringLiteral: shape.protocolName))
        ]

        return ActorDeclSyntax(
            attributes: AttributeListSyntax([]),
            modifiers: modifiers(for: .mockType),
            name: .identifier(shape.mockClassName),
            inheritanceClause: InheritanceClauseSyntax(
                inheritedTypes: InheritedTypeListSyntax(inheritedTypes)
            ),
            memberBlock: memberBlock
        )
    }

    /// The per-requirement mock members, in protocol declaration order and with any
    /// `#if` structure preserved. Each requirement's tracking model is computed once
    /// here and handed to the per-kind generator.
    private func generateMockMembers() -> [MemberBlockItemSyntax] {
        return mapMemberBlockItemsPreservingIfConfig { requirement in
            switch requirement {
            case .initializer(let initDecl):
                return generateInitializerMock(
                    initDecl,
                    requirement: initializerTrackingRequirement(for: initDecl, overloads: overloads)
                )

            case .function(let funcDecl):
                return generateFunctionMock(
                    funcDecl,
                    requirement: functionTrackingRequirement(
                        for: funcDecl,
                        scope: requirement.scope,
                        leavesMockIsolation: requirement.leavesMockIsolation,
                        overloads: overloads
                    )
                )

            case .variable(let varDecl):
                return generateVariableMock(
                    varDecl,
                    scope: requirement.scope,
                    leavesMockIsolation: requirement.leavesMockIsolation
                )

            case .subscript(let subscriptDecl):
                return generateSubscriptMock(
                    subscriptDecl,
                    requirement: subscriptTrackingRequirement(
                        for: subscriptDecl,
                        leavesMockIsolation: requirement.leavesMockIsolation,
                        overloads: overloads
                    )
                )

            // Associated types and type aliases are emitted ahead of the other members
            // (see `generateAssociatedTypeMembers`); an unsupported member never reaches
            // generation, since diagnostics reject the protocol first.
            case .associatedType, .typeAlias, .unsupported:
                return []
            }
        }
    }

    /// Generates an explicit parameterless initializer for the mock class.
    /// For `public` / `package` protocols, the default synthesized initializer is `internal`,
    /// which prevents the mock from being instantiated across module boundaries. This is only
    /// emitted for root mocks; a mock that subclasses a parent mock inherits the parent's
    /// initializers instead.
    private func generateInit() -> DeclSyntax {
        let initDecl = InitializerDeclSyntax(
            modifiers: modifiers(for: .member),
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
