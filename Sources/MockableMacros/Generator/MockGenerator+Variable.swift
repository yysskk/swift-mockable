import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Variable Mock Generation

extension MockGenerator {
    func generateVariableMock(_ varDecl: VariableDeclSyntax) -> [MemberBlockItemSyntax] {
        var members: [MemberBlockItemSyntax] = []

        for binding in varDecl.bindings {
            guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                  let typeAnnotation = binding.typeAnnotation
            else {
                continue
            }

            let varName = identifier.identifier.text
            let varType = typeAnnotation.type

            let isGetOnly = Self.isGetOnlyProperty(binding: binding)

            if isSendable {
                // For Sendable protocols, generate computed properties that access the Mutex
                // For get-only properties, also generate a _varName setter property
                if isGetOnly {
                    let setterProperty = generateSendableBackingSetterProperty(
                        varName: varName,
                        varType: varType
                    )
                    members.append(MemberBlockItemSyntax(decl: setterProperty))
                }

                let computedProperty = generateSendableVariableProperty(
                    varName: varName,
                    varType: varType,
                    isGetOnly: isGetOnly
                )
                members.append(MemberBlockItemSyntax(decl: computedProperty))
            } else {
                if isGetOnly {
                    // Generate backing storage
                    let storageProperty = generateGetOnlyStorageProperty(varName: varName, varType: varType)
                    members.append(MemberBlockItemSyntax(decl: storageProperty))

                    // Generate computed property
                    let computedProperty = generateComputedGetProperty(
                        varDecl: varDecl,
                        varName: varName,
                        varType: varType
                    )
                    members.append(MemberBlockItemSyntax(decl: computedProperty))
                } else {
                    // Generate stored property (possibly with backing storage for non-optional types)
                    let storedPropertyMembers = generateStoredProperty(
                        varDecl: varDecl,
                        varName: varName,
                        varType: varType
                    )
                    members.append(contentsOf: storedPropertyMembers)
                }
            }
        }

        return members
    }

    static func isGetOnlyProperty(binding: PatternBindingSyntax) -> Bool {
        guard let accessorBlock = binding.accessorBlock else {
            return false
        }

        switch accessorBlock.accessors {
        case .getter:
            return true
        case .accessors(let accessors):
            let hasGetter = accessors.contains { $0.accessorSpecifier.tokenKind == .keyword(.get) }
            let hasSetter = accessors.contains { $0.accessorSpecifier.tokenKind == .keyword(.set) }
            return hasGetter && !hasSetter
        }
    }

    func generateSendableBackingSetterProperty(
        varName: String,
        varType: TypeSyntax
    ) -> VariableDeclSyntax {
        let isOptional = varType.is(OptionalTypeSyntax.self) || varType.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)

        let storageType: TypeSyntax
        if isOptional {
            storageType = varType.trimmed
        } else {
            storageType = TypeSyntax(OptionalTypeSyntax(wrappedType: varType.trimmed))
        }

        let getterBody = "_storage.withLock { $0._\(varName) }"
        let setterBody = "_storage.withLock { $0._\(varName) = newValue }"

        return VariableDeclSyntax(
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.public))
            ]),
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier("_\(varName)")),
                    typeAnnotation: TypeAnnotationSyntax(type: storageType),
                    accessorBlock: AccessorBlockSyntax(
                        accessors: .accessors(AccessorDeclListSyntax([
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.get),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: getterBody)))
                                    ])
                                )
                            ),
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.set),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: setterBody)))
                                    ])
                                )
                            )
                        ]))
                    )
                )
            ])
        )
    }

    func generateSendableVariableProperty(
        varName: String,
        varType: TypeSyntax,
        isGetOnly: Bool
    ) -> VariableDeclSyntax {
        let isOptional = varType.is(OptionalTypeSyntax.self) || varType.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)

        let getterBody: String
        if isOptional {
            getterBody = "_storage.withLock { $0._\(varName) }"
        } else {
            getterBody = "_storage.withLock { $0._\(varName)! }"
        }

        if isGetOnly {
            return VariableDeclSyntax(
                modifiers: DeclModifierListSyntax([
                    DeclModifierSyntax(name: .keyword(.public))
                ]),
                bindingSpecifier: .keyword(.var),
                bindings: PatternBindingListSyntax([
                    PatternBindingSyntax(
                        pattern: IdentifierPatternSyntax(identifier: .identifier(varName)),
                        typeAnnotation: TypeAnnotationSyntax(type: varType.trimmed),
                        accessorBlock: AccessorBlockSyntax(
                            accessors: .getter(CodeBlockItemListSyntax([
                                CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: getterBody)))
                            ]))
                        )
                    )
                ])
            )
        } else {
            let setterBody = "_storage.withLock { $0._\(varName) = newValue }"

            return VariableDeclSyntax(
                modifiers: DeclModifierListSyntax([
                    DeclModifierSyntax(name: .keyword(.public))
                ]),
                bindingSpecifier: .keyword(.var),
                bindings: PatternBindingListSyntax([
                    PatternBindingSyntax(
                        pattern: IdentifierPatternSyntax(identifier: .identifier(varName)),
                        typeAnnotation: TypeAnnotationSyntax(type: varType.trimmed),
                        accessorBlock: AccessorBlockSyntax(
                            accessors: .accessors(AccessorDeclListSyntax([
                                AccessorDeclSyntax(
                                    accessorSpecifier: .keyword(.get),
                                    body: CodeBlockSyntax(
                                        statements: CodeBlockItemListSyntax([
                                            CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: getterBody)))
                                        ])
                                    )
                                ),
                                AccessorDeclSyntax(
                                    accessorSpecifier: .keyword(.set),
                                    body: CodeBlockSyntax(
                                        statements: CodeBlockItemListSyntax([
                                            CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: setterBody)))
                                        ])
                                    )
                                )
                            ]))
                        )
                    )
                ])
            )
        }
    }

    private func generateGetOnlyStorageProperty(varName: String, varType: TypeSyntax) -> VariableDeclSyntax {
        let isOptional = varType.is(OptionalTypeSyntax.self) ||
                         varType.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)

        let storageType: TypeSyntax
        let initializer: InitializerClauseSyntax?

        if isOptional {
            storageType = varType.trimmed
            initializer = InitializerClauseSyntax(value: NilLiteralExprSyntax())
        } else {
            storageType = TypeSyntax(OptionalTypeSyntax(wrappedType: varType.trimmed))
            initializer = InitializerClauseSyntax(value: NilLiteralExprSyntax())
        }

        return VariableDeclSyntax(
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.public))
            ]),
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier("_\(varName)")),
                    typeAnnotation: TypeAnnotationSyntax(type: storageType),
                    initializer: initializer
                )
            ])
        )
    }

    private func generateComputedGetProperty(
        varDecl: VariableDeclSyntax,
        varName: String,
        varType: TypeSyntax
    ) -> VariableDeclSyntax {
        let isOptional = varType.is(OptionalTypeSyntax.self) ||
                         varType.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)

        let getterBody: String
        if isOptional {
            getterBody = "_\(varName)"
        } else {
            getterBody = "_\(varName)!"
        }

        return VariableDeclSyntax(
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.public))
            ]),
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier(varName)),
                    typeAnnotation: TypeAnnotationSyntax(type: varType.trimmed),
                    accessorBlock: AccessorBlockSyntax(
                        accessors: .getter(CodeBlockItemListSyntax([
                            CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: getterBody)))
                        ]))
                    )
                )
            ])
        )
    }

    private func generateStoredProperty(
        varDecl: VariableDeclSyntax,
        varName: String,
        varType: TypeSyntax
    ) -> [MemberBlockItemSyntax] {
        let isOptional = varType.is(OptionalTypeSyntax.self) ||
                         varType.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)

        if isOptional {
            // For optional types, generate a simple stored property
            let storedProperty = VariableDeclSyntax(
                modifiers: DeclModifierListSyntax([
                    DeclModifierSyntax(name: .keyword(.public))
                ]),
                bindingSpecifier: .keyword(.var),
                bindings: PatternBindingListSyntax([
                    PatternBindingSyntax(
                        pattern: IdentifierPatternSyntax(identifier: .identifier(varName)),
                        typeAnnotation: TypeAnnotationSyntax(type: varType.trimmed),
                        initializer: InitializerClauseSyntax(value: NilLiteralExprSyntax())
                    )
                ])
            )
            return [MemberBlockItemSyntax(decl: storedProperty)]
        } else {
            // For non-optional get-set properties, generate backing storage + computed property
            // to ensure protocol conformance
            let backingProperty = VariableDeclSyntax(
                modifiers: DeclModifierListSyntax([
                    DeclModifierSyntax(name: .keyword(.public))
                ]),
                bindingSpecifier: .keyword(.var),
                bindings: PatternBindingListSyntax([
                    PatternBindingSyntax(
                        pattern: IdentifierPatternSyntax(identifier: .identifier("_\(varName)")),
                        typeAnnotation: TypeAnnotationSyntax(
                            type: TypeSyntax(OptionalTypeSyntax(wrappedType: varType.trimmed))
                        ),
                        initializer: InitializerClauseSyntax(value: NilLiteralExprSyntax())
                    )
                ])
            )

            let computedProperty = VariableDeclSyntax(
                modifiers: DeclModifierListSyntax([
                    DeclModifierSyntax(name: .keyword(.public))
                ]),
                bindingSpecifier: .keyword(.var),
                bindings: PatternBindingListSyntax([
                    PatternBindingSyntax(
                        pattern: IdentifierPatternSyntax(identifier: .identifier(varName)),
                        typeAnnotation: TypeAnnotationSyntax(type: varType.trimmed),
                        accessorBlock: AccessorBlockSyntax(
                            accessors: .accessors(AccessorDeclListSyntax([
                                AccessorDeclSyntax(
                                    accessorSpecifier: .keyword(.get),
                                    body: CodeBlockSyntax(
                                        statements: CodeBlockItemListSyntax([
                                            CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_\(varName)!")))
                                        ])
                                    )
                                ),
                                AccessorDeclSyntax(
                                    accessorSpecifier: .keyword(.set),
                                    body: CodeBlockSyntax(
                                        statements: CodeBlockItemListSyntax([
                                            CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_\(varName) = newValue")))
                                        ])
                                    )
                                )
                            ]))
                        )
                    )
                ])
            )

            return [
                MemberBlockItemSyntax(decl: backingProperty),
                MemberBlockItemSyntax(decl: computedProperty)
            ]
        }
    }
}
