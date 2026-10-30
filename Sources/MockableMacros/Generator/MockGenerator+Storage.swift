import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Sendable Support

extension MockGenerator {
    /// Generates the private `MockableLock`-wrapped storage property (`_storage` or
    /// `_staticStorage`) that guards a `Sendable`/actor mock's tracking state. The lock
    /// wraps a `Storage`/`StaticStorage` value holding every requirement's counters,
    /// captured arguments, and handlers.
    func generateLockProperty(for scope: MemberScope) -> VariableDeclSyntax {
        let propertyName = MockNaming.storageName(for: scope)
        let storageTypeName = MockNaming.storageTypeName(for: scope)
        var modifiers = [
            DeclModifierSyntax(name: .keyword(.private))
        ]
        modifiers.append(contentsOf: scope.modifiers)
        // A `let` of a Sendable type is safe to read from anywhere, and a nonisolated
        // member has to: on an isolated mock the lock would otherwise be as isolated
        // as the state it guards. Actor mocks need no modifier — an actor's stored
        // `let` and its static members are already reachable from outside.
        if needsNonisolatedStorage && !shape.isActor {
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

    /// Builds the storage struct for the members in `scope` from the tracking model —
    /// `Storage` for instance members, `StaticStorage` for type members — with a stored
    /// field per slot of every such requirement and the protocol's `#if` structure
    /// preserved.
    func generateStorageStruct(for scope: MemberScope) -> StructDeclSyntax {
        let storageMembers = mapMemberBlockItemsPreservingIfConfig { requirement in
            // Initializers are never type members, so their tracking fields live only
            // in the instance `Storage` struct.
            guard requirement.scope == scope else {
                return []
            }

            return trackingRequirements(for: requirement).flatMap { tracking in
                tracking.trackingFields(model: .lockBacked).map { field in
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
            name: .identifier(MockNaming.storageTypeName(for: scope)),
            memberBlock: MemberBlockSyntax(
                leftBrace: .leftBraceToken(trailingTrivia: .newline),
                members: MemberBlockItemListSyntax(storageMembers),
                rightBrace: .rightBraceToken(leadingTrivia: .newline)
            )
        )
    }
}
