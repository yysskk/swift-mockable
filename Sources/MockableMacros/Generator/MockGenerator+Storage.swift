import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Sendable Support

extension MockGenerator {
    /// Generates the private `MockableLock`-wrapped storage property (`_storage` or
    /// `_staticStorage`) that guards a `Sendable`/actor mock's tracking state. The lock
    /// wraps a `Storage`/`StaticStorage` value holding every requirement's counters,
    /// captured arguments, and handlers.
    func generateLockProperty(
        propertyName: String = MockNaming.instanceStorageName,
        storageTypeName: String = MockNaming.storageTypeName,
        isStatic: Bool = false
    ) -> VariableDeclSyntax {
        var modifiers = [
            DeclModifierSyntax(name: .keyword(.private))
        ]
        modifiers.append(contentsOf: Self.typeMemberModifiers(isTypeMember: isStatic))
        // A `let` of a Sendable type is safe to read from anywhere, and a nonisolated
        // witness has to: on an isolated mock the lock would otherwise be as isolated
        // as the state it guards. Actor mocks need no modifier — an actor's stored
        // `let` and its static members are already reachable from outside.
        if hasNonisolatedRequirements && !isActor {
            modifiers.append(DeclModifierSyntax(name: .keyword(.nonisolated)))
        }

        return VariableDeclSyntax(
            modifiers: DeclModifierListSyntax(modifiers),
            bindingSpecifier: .keyword(.let),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier(propertyName)),
                    typeAnnotation: nil,
                    initializer: InitializerClauseSyntax(
                        value: FunctionCallExprSyntax(
                            calledExpression: GenericSpecializationExprSyntax(
                                expression: DeclReferenceExprSyntax(baseName: .identifier("MockableLock")),
                                genericArgumentClause: GenericArgumentClauseSyntax(
                                    arguments: GenericArgumentListSyntax([
                                        makeGenericArgument(type: TypeSyntax(stringLiteral: storageTypeName))
                                    ])
                                )
                            ),
                            leftParen: .leftParenToken(),
                            arguments: LabeledExprListSyntax([
                                LabeledExprSyntax(
                                    expression: FunctionCallExprSyntax(
                                        calledExpression: DeclReferenceExprSyntax(baseName: .identifier(storageTypeName)),
                                        leftParen: .leftParenToken(),
                                        arguments: LabeledExprListSyntax([]),
                                        rightParen: .rightParenToken()
                                    )
                                )
                            ]),
                            rightParen: .rightParenToken()
                        )
                    )
                )
            ])
        )
    }

    /// The `Storage` struct holding the tracking state for the mock's instance members.
    func generateStorageStruct() -> StructDeclSyntax {
        generateStorageStruct(named: MockNaming.storageTypeName, includeTypeMembers: false)
    }

    /// The `StaticStorage` struct holding the tracking state for the mock's `static` members.
    func generateStaticStorageStruct() -> StructDeclSyntax {
        generateStorageStruct(named: MockNaming.staticStorageTypeName, includeTypeMembers: true)
    }

    /// Builds one storage struct from the tracking model: a stored field per slot of
    /// every requirement on the matching side of the instance/static split, with the
    /// protocol's `#if` structure preserved.
    private func generateStorageStruct(
        named storageName: String,
        includeTypeMembers: Bool
    ) -> StructDeclSyntax {
        let overloads = makeOverloadContext()

        let storageMembers = mapMemberBlockItemsPreservingIfConfig { decl in
            // Initializers are never type members, so their tracking fields live only
            // in the instance `Storage` struct.
            guard Self.isTypeMember(decl) == includeTypeMembers else {
                return []
            }

            return trackingRequirements(for: decl, overloads: overloads).flatMap { requirement in
                requirement.trackingFields(model: .lockBacked).map { field in
                    MemberBlockItemSyntax(decl: Self.makeStoredProperty(
                        name: field.name,
                        type: field.type,
                        initializer: field.initialValue
                    ))
                }
            }
        }

        return StructDeclSyntax(
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.private))
            ]),
            name: .identifier(storageName),
            memberBlock: MemberBlockSyntax(
                leftBrace: .leftBraceToken(trailingTrivia: .newline),
                members: MemberBlockItemListSyntax(storageMembers),
                rightBrace: .rightBraceToken(leadingTrivia: .newline)
            )
        )
    }
}
