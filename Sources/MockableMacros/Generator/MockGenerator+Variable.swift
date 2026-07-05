import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Variable Mock Generation

extension MockGenerator {
    func generateVariableMock(
        _ varDecl: VariableDeclSyntax
    ) -> [MemberBlockItemSyntax] {
        var members: [MemberBlockItemSyntax] = []
        let isTypeMember = Self.isTypeMember(varDecl.modifiers)
        let shouldUseLockBasedStorage = usesLockBasedStorage(isTypeMember: isTypeMember)

        for binding in varDecl.bindings {
            guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                  let typeAnnotation = binding.typeAnnotation
            else {
                continue
            }

            let varName = identifier.identifier.text
            let varType = typeAnnotation.type
            let isGetOnly = Self.isGetOnlyProperty(binding: binding)

            // Effectful read-only properties (`get async`/`get throws`) are mocked with
            // a handler and a call counter instead of backing storage: a stored value
            // cannot model a thrown error, and the handler mirrors the function model.
            if let effectfulGetter = Self.effectfulGetter(of: binding) {
                members.append(contentsOf: generateEffectfulGetterMock(
                    varName: varName,
                    varType: varType,
                    getter: effectfulGetter,
                    isTypeMember: isTypeMember
                ))
                continue
            }

            if shouldUseLockBasedStorage {
                let backingProperty = generateLockBasedBackingSetterProperty(
                    varName: varName,
                    varType: varType,
                    isTypeMember: isTypeMember
                )
                members.append(MemberBlockItemSyntax(decl: backingProperty))

                let computedProperty = generateLockBasedVariableProperty(
                    varName: varName,
                    varType: varType,
                    isGetOnly: isGetOnly,
                    isTypeMember: isTypeMember
                )
                members.append(MemberBlockItemSyntax(decl: computedProperty))
                continue
            }

            if isGetOnly {
                let storageProperty = generateGetOnlyStorageProperty(
                    varName: varName,
                    varType: varType,
                    isTypeMember: isTypeMember
                )
                members.append(MemberBlockItemSyntax(decl: storageProperty))

                let computedProperty = generateComputedGetProperty(
                    varName: varName,
                    varType: varType,
                    isTypeMember: isTypeMember
                )
                members.append(MemberBlockItemSyntax(decl: computedProperty))
            } else {
                let storedPropertyMembers = generateStoredProperty(
                    varName: varName,
                    varType: varType,
                    isTypeMember: isTypeMember
                )
                members.append(contentsOf: storedPropertyMembers)
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

    /// Returns the `get` accessor of a binding when it carries `async`/`throws`
    /// effects (e.g. `var token: String { get async throws }`), or `nil` otherwise.
    /// Properties with an effectful getter cannot have a setter (SE-0310).
    static func effectfulGetter(of binding: PatternBindingSyntax) -> AccessorDeclSyntax? {
        guard let accessorBlock = binding.accessorBlock,
              case .accessors(let accessors) = accessorBlock.accessors else {
            return nil
        }
        return accessors.first { accessor in
            accessor.accessorSpecifier.tokenKind == .keyword(.get) && accessor.effectSpecifiers != nil
        }
    }

    /// The handler closure type for an effectful read-only property, e.g.
    /// `() async throws -> String`. The handler is untyped-throwing even for a
    /// typed-throws accessor (`get throws(E)`) — the generated getter re-throws the
    /// typed error via a `catch` — so a typed error type is dropped here.
    static func effectfulGetterClosureType(
        varType: TypeSyntax,
        effects: AccessorEffectSpecifiersSyntax?
    ) -> String {
        var effectsText = ""
        if effects?.asyncSpecifier != nil {
            effectsText += " async"
        }
        if effects?.hasThrowsEffect == true {
            effectsText += " throws"
        }
        return "()\(effectsText) -> \(varType.trimmedDescription)"
    }

    private func generateEffectfulGetterMock(
        varName: String,
        varType: TypeSyntax,
        getter: AccessorDeclSyntax,
        isTypeMember: Bool
    ) -> [MemberBlockItemSyntax] {
        let effects = getter.effectSpecifiers
        let isAsync = effects?.asyncSpecifier != nil
        let isThrows = effects?.hasThrowsEffect ?? false
        let closureType = Self.effectfulGetterClosureType(varType: varType, effects: effects)
        let shouldUseLockBasedStorage = usesLockBasedStorage(isTypeMember: isTypeMember)

        var members: [MemberBlockItemSyntax] = []

        let callCountProperty = generateFunctionStorageProperty(
            name: MockNaming.callCount(varName),
            type: TypeSyntax(stringLiteral: "Int"),
            initializer: ExprSyntax(IntegerLiteralExprSyntax(literal: .integerLiteral("0"))),
            isTypeMember: isTypeMember
        )
        members.append(MemberBlockItemSyntax(decl: callCountProperty))

        let handlerProperty = generateFunctionStorageProperty(
            name: MockNaming.handler(varName),
            type: TypeSyntax(stringLiteral: "(@Sendable \(closureType))?"),
            initializer: ExprSyntax(NilLiteralExprSyntax()),
            isTypeMember: isTypeMember
        )
        members.append(MemberBlockItemSyntax(decl: handlerProperty))

        let invokePrefix = "\(isThrows ? "try " : "")\(isAsync ? "await " : "")"
        let elseBody = Self.defaultReturnStatement(for: varType)
            ?? "fatalError(\"\\(Self.self).\(MockNaming.handler(varName)) is not set\")"
        let errorType = effects?.throwsErrorType?.trimmedDescription

        var getterStatements: [CodeBlockItemSyntax] = []
        if shouldUseLockBasedStorage {
            let storageName = Self.storagePropertyName(isTypeMember: isTypeMember)
            getterStatements.append(CodeBlockItemSyntax(item: .decl(DeclSyntax(stringLiteral: """
let _handler = \(storageName).withLock { storage -> (@Sendable \(closureType))? in
    storage.\(MockNaming.callCount(varName)) += 1
    return storage.\(MockNaming.handler(varName))
}
"""))))
            getterStatements.append(CodeBlockItemSyntax(leadingTrivia: .newline, item: .stmt(StmtSyntax(stringLiteral: """
guard let _handler else {
    \(elseBody)
}
"""))))
        } else {
            getterStatements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "\(MockNaming.callCount(varName)) += 1"))))
            getterStatements.append(CodeBlockItemSyntax(leadingTrivia: .newline, item: .stmt(StmtSyntax(stringLiteral: """
guard let _handler = \(MockNaming.handler(varName)) else {
    \(elseBody)
}
"""))))
        }
        if let errorType {
            getterStatements.append(CodeBlockItemSyntax(
                leadingTrivia: .newline,
                item: Self.buildTypedThrowsCatch(
                    innerLines: ["return \(invokePrefix)_handler()"],
                    errorType: errorType
                ).item
            ))
        } else {
            getterStatements.append(CodeBlockItemSyntax(
                leadingTrivia: .newline,
                item: .stmt(StmtSyntax(stringLiteral: "return \(invokePrefix)_handler()"))
            ))
        }

        // The protocol witness stays actor-isolated on actor mocks (like every other
        // generated witness); only the auxiliary CallCount/Handler storage members are
        // `nonisolated`, which they already get via `generateFunctionStorageProperty`.
        let property = VariableDeclSyntax(
            modifiers: buildModifiers(additional: Self.typeMemberModifiers(isTypeMember: isTypeMember)),
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier(varName)),
                    typeAnnotation: TypeAnnotationSyntax(type: varType.trimmed),
                    accessorBlock: AccessorBlockSyntax(
                        accessors: .accessors(AccessorDeclListSyntax([
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.get),
                                effectSpecifiers: getter.effectSpecifiers?.trimmed,
                                body: CodeBlockSyntax(
                                    leftBrace: .leftBraceToken(trailingTrivia: .newline),
                                    statements: CodeBlockItemListSyntax(getterStatements),
                                    rightBrace: .rightBraceToken(leadingTrivia: .newline)
                                )
                            )
                        ]))
                    )
                )
            ])
        )
        members.append(MemberBlockItemSyntax(decl: property))

        return members
    }

    private func generateLockBasedBackingSetterProperty(
        varName: String,
        varType: TypeSyntax,
        isTypeMember: Bool
    ) -> VariableDeclSyntax {
        let isOptional = varType.is(OptionalTypeSyntax.self) || varType.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)
        let storageName = Self.storagePropertyName(isTypeMember: isTypeMember)

        let storageType: TypeSyntax
        if isOptional {
            storageType = varType.trimmed
        } else {
            storageType = TypeSyntax(OptionalTypeSyntax(wrappedType: varType.trimmed))
        }

        let getterBody = "\(storageName).withLock { $0.\(MockNaming.variableBacking(varName)) }"
        let setterBody = "\(storageName).withLock { $0.\(MockNaming.variableBacking(varName)) = newValue }"
        var additionalModifiers = Self.typeMemberModifiers(isTypeMember: isTypeMember)
        if !isTypeMember {
            additionalModifiers.append(contentsOf: storageBackedMemberModifiers())
        }

        return VariableDeclSyntax(
            modifiers: buildModifiers(additional: additionalModifiers),
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier(MockNaming.variableBacking(varName))),
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

    private func generateLockBasedVariableProperty(
        varName: String,
        varType: TypeSyntax,
        isGetOnly: Bool,
        isTypeMember: Bool
    ) -> VariableDeclSyntax {
        let isOptional = varType.is(OptionalTypeSyntax.self) || varType.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)
        let storageName = Self.storagePropertyName(isTypeMember: isTypeMember)
        let additionalModifiers = Self.typeMemberModifiers(isTypeMember: isTypeMember)

        let getterBody: String
        if isOptional {
            getterBody = "\(storageName).withLock { $0.\(MockNaming.variableBacking(varName)) }"
        } else {
            getterBody = "\(storageName).withLock { $0.\(MockNaming.variableBacking(varName))! }"
        }

        if isGetOnly {
            return VariableDeclSyntax(
                modifiers: buildModifiers(additional: additionalModifiers),
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

        let setterBody = "\(storageName).withLock { $0.\(MockNaming.variableBacking(varName)) = newValue }"
        return VariableDeclSyntax(
            modifiers: buildModifiers(additional: additionalModifiers),
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

    private func generateGetOnlyStorageProperty(
        varName: String,
        varType: TypeSyntax,
        isTypeMember: Bool
    ) -> VariableDeclSyntax {
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
            modifiers: buildModifiers(additional: Self.typeMemberModifiers(isTypeMember: isTypeMember)),
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier(MockNaming.variableBacking(varName))),
                    typeAnnotation: TypeAnnotationSyntax(type: storageType),
                    initializer: initializer
                )
            ])
        )
    }

    private func generateComputedGetProperty(
        varName: String,
        varType: TypeSyntax,
        isTypeMember: Bool
    ) -> VariableDeclSyntax {
        let isOptional = varType.is(OptionalTypeSyntax.self) ||
                         varType.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)

        let getterBody: String
        if isOptional {
            getterBody = "\(MockNaming.variableBacking(varName))"
        } else {
            getterBody = "\(MockNaming.variableBacking(varName))!"
        }

        return VariableDeclSyntax(
            modifiers: buildModifiers(additional: Self.typeMemberModifiers(isTypeMember: isTypeMember)),
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
        varName: String,
        varType: TypeSyntax,
        isTypeMember: Bool
    ) -> [MemberBlockItemSyntax] {
        let isOptional = varType.is(OptionalTypeSyntax.self) ||
                         varType.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)
        let additionalModifiers = Self.typeMemberModifiers(isTypeMember: isTypeMember)

        if isOptional {
            let storedProperty = VariableDeclSyntax(
                modifiers: buildModifiers(additional: additionalModifiers),
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
        }

        let backingProperty = VariableDeclSyntax(
            modifiers: buildModifiers(additional: additionalModifiers),
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier(MockNaming.variableBacking(varName))),
                    typeAnnotation: TypeAnnotationSyntax(
                        type: TypeSyntax(OptionalTypeSyntax(wrappedType: varType.trimmed))
                    ),
                    initializer: InitializerClauseSyntax(value: NilLiteralExprSyntax())
                )
            ])
        )

        let computedProperty = VariableDeclSyntax(
            modifiers: buildModifiers(additional: additionalModifiers),
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
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "\(MockNaming.variableBacking(varName))!")))
                                    ])
                                )
                            ),
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.set),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "\(MockNaming.variableBacking(varName)) = newValue")))
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
