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

    private func generateStorageStruct(
        named storageName: String,
        includeTypeMembers: Bool
    ) -> StructDeclSyntax {
        // Group methods by name to detect overloads (including conditional members)
        let methodGroups = groupMethodsByNameIncludingConditional()
        let initializers = collectInitializers()

        let storageMembers = mapMemberBlockItemsPreservingIfConfig { decl in
            var generatedMembers: [MemberBlockItemSyntax] = []
            let isTypeMember = Self.isTypeMember(decl)

            guard isTypeMember == includeTypeMembers else {
                return generatedMembers
            }

            if let initDecl = decl.as(InitializerDeclSyntax.self) {
                // Initializers are never type members, so their tracking fields live only in
                // the instance `Storage` struct.
                let identifier = Self.initializerIdentifier(for: initDecl, in: initializers)
                let parameters = initDecl.signature.parameterClause.parameters
                let genericParamNames = Self.extractGenericParameterNames(from: initDecl)

                let callCountDecl = VariableDeclSyntax(
                    bindingSpecifier: .keyword(.var),
                    bindings: PatternBindingListSyntax([
                        PatternBindingSyntax(
                            pattern: IdentifierPatternSyntax(identifier: .identifier(MockNaming.callCount(identifier))),
                            typeAnnotation: TypeAnnotationSyntax(type: TypeSyntax(stringLiteral: "Int")),
                            initializer: InitializerClauseSyntax(value: IntegerLiteralExprSyntax(literal: .integerLiteral("0")))
                        )
                    ])
                )
                generatedMembers.append(MemberBlockItemSyntax(decl: callCountDecl))

                let tupleType = Self.buildCallArgsTupleType(parameters: parameters, genericParamNames: genericParamNames)
                let callArgsDecl = VariableDeclSyntax(
                    bindingSpecifier: .keyword(.var),
                    bindings: PatternBindingListSyntax([
                        PatternBindingSyntax(
                            pattern: IdentifierPatternSyntax(identifier: .identifier(MockNaming.callArgs(identifier))),
                            typeAnnotation: TypeAnnotationSyntax(type: ArrayTypeSyntax(element: tupleType)),
                            initializer: InitializerClauseSyntax(value: ArrayExprSyntax(elements: ArrayElementListSyntax([])))
                        )
                    ])
                )
                generatedMembers.append(MemberBlockItemSyntax(decl: callArgsDecl))

                return generatedMembers
            }

            if let funcDecl = decl.as(FunctionDeclSyntax.self) {
                let funcName = funcDecl.name.text
                let methodGroup = methodGroups[funcName] ?? []
                let isOverloaded = methodGroup.count > 1
                let suffix = isOverloaded ? Self.functionIdentifierSuffix(from: funcDecl, in: methodGroup) : ""
                let identifier = suffix.isEmpty ? funcName : "\(funcName)\(suffix)"
                let parameters = funcDecl.signature.parameterClause.parameters
                let returnType = funcDecl.signature.returnClause?.type
                let isAsync = funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil
                // `rethrows` requirements get a non-throwing handler (see MockGenerator+Function).
                let handlerThrows = (funcDecl.signature.effectSpecifiers?.hasThrowsEffect ?? false)
                    && (funcDecl.signature.effectSpecifiers?.isRethrows != true)
                let genericParamNames = Self.extractGenericParameterNames(from: funcDecl)

                // CallCount
                let callCountDecl = VariableDeclSyntax(
                    bindingSpecifier: .keyword(.var),
                    bindings: PatternBindingListSyntax([
                        PatternBindingSyntax(
                            pattern: IdentifierPatternSyntax(identifier: .identifier(MockNaming.callCount(identifier))),
                            typeAnnotation: TypeAnnotationSyntax(type: TypeSyntax(stringLiteral: "Int")),
                            initializer: InitializerClauseSyntax(value: IntegerLiteralExprSyntax(literal: .integerLiteral("0")))
                        )
                    ])
                )
                generatedMembers.append(MemberBlockItemSyntax(decl: callCountDecl))

                // CallArgs
                let tupleType = Self.buildCallArgsTupleType(parameters: parameters, genericParamNames: genericParamNames)
                let callArgsDecl = VariableDeclSyntax(
                    bindingSpecifier: .keyword(.var),
                    bindings: PatternBindingListSyntax([
                        PatternBindingSyntax(
                            pattern: IdentifierPatternSyntax(identifier: .identifier(MockNaming.callArgs(identifier))),
                            typeAnnotation: TypeAnnotationSyntax(type: ArrayTypeSyntax(element: tupleType)),
                            initializer: InitializerClauseSyntax(value: ArrayExprSyntax(elements: ArrayElementListSyntax([])))
                        )
                    ])
                )
                generatedMembers.append(MemberBlockItemSyntax(decl: callArgsDecl))

                // Handler
                let closureType = buildFunctionClosureType(
                    parameters: parameters,
                    returnType: returnType,
                    isAsync: isAsync,
                    isThrows: handlerThrows,
                    genericParamNames: genericParamNames
                )

                let handlerDecl = VariableDeclSyntax(
                    bindingSpecifier: .keyword(.var),
                    bindings: PatternBindingListSyntax([
                        PatternBindingSyntax(
                            pattern: IdentifierPatternSyntax(identifier: .identifier(MockNaming.handler(identifier))),
                            typeAnnotation: TypeAnnotationSyntax(
                                type: OptionalTypeSyntax(wrappedType: TypeSyntax(stringLiteral: "(@Sendable \(closureType))"))
                            ),
                            initializer: InitializerClauseSyntax(value: NilLiteralExprSyntax())
                        )
                    ])
                )
                generatedMembers.append(MemberBlockItemSyntax(decl: handlerDecl))
            } else if let varDecl = decl.as(VariableDeclSyntax.self) {
                for binding in varDecl.bindings {
                    guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                          let typeAnnotation = binding.typeAnnotation else { continue }

                    let varName = identifier.identifier.text
                    let varType = typeAnnotation.type

                    // Effectful read-only properties are handler-based (no `_name` backing).
                    if let effectfulGetter = Self.effectfulGetter(of: binding) {
                        let closureType = Self.effectfulGetterClosureType(
                            varType: varType,
                            effects: effectfulGetter.effectSpecifiers
                        )

                        let callCountDecl = VariableDeclSyntax(
                            bindingSpecifier: .keyword(.var),
                            bindings: PatternBindingListSyntax([
                                PatternBindingSyntax(
                                    pattern: IdentifierPatternSyntax(identifier: .identifier(MockNaming.callCount(varName))),
                                    typeAnnotation: TypeAnnotationSyntax(type: TypeSyntax(stringLiteral: "Int")),
                                    initializer: InitializerClauseSyntax(value: IntegerLiteralExprSyntax(literal: .integerLiteral("0")))
                                )
                            ])
                        )
                        generatedMembers.append(MemberBlockItemSyntax(decl: callCountDecl))

                        let handlerDecl = VariableDeclSyntax(
                            bindingSpecifier: .keyword(.var),
                            bindings: PatternBindingListSyntax([
                                PatternBindingSyntax(
                                    pattern: IdentifierPatternSyntax(identifier: .identifier(MockNaming.handler(varName))),
                                    typeAnnotation: TypeAnnotationSyntax(
                                        type: OptionalTypeSyntax(wrappedType: TypeSyntax(stringLiteral: "(@Sendable \(closureType))"))
                                    ),
                                    initializer: InitializerClauseSyntax(value: NilLiteralExprSyntax())
                                )
                            ])
                        )
                        generatedMembers.append(MemberBlockItemSyntax(decl: handlerDecl))
                        continue
                    }

                    let isOptional = varType.is(OptionalTypeSyntax.self) || varType.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)

                    let storageType: TypeSyntax
                    if isOptional {
                        storageType = varType.trimmed
                    } else {
                        storageType = TypeSyntax(OptionalTypeSyntax(wrappedType: varType.trimmed))
                    }

                    let storageProp = VariableDeclSyntax(
                        bindingSpecifier: .keyword(.var),
                        bindings: PatternBindingListSyntax([
                            PatternBindingSyntax(
                                pattern: IdentifierPatternSyntax(identifier: .identifier(MockNaming.variableBacking(varName))),
                                typeAnnotation: TypeAnnotationSyntax(type: storageType),
                                initializer: InitializerClauseSyntax(value: NilLiteralExprSyntax())
                            )
                        ])
                    )
                    generatedMembers.append(MemberBlockItemSyntax(decl: storageProp))
                }
            } else if let subscriptDecl = decl.as(SubscriptDeclSyntax.self) {
                let parameters = subscriptDecl.parameterClause.parameters
                let returnType = subscriptDecl.returnClause.type
                let genericParamNames = Self.extractGenericParameterNames(from: subscriptDecl)
                let isGetOnly = Self.isGetOnlySubscript(subscriptDecl)
                let suffix = Self.subscriptIdentifierSuffix(from: subscriptDecl)

                // SubscriptCallCount
                let callCountDecl = VariableDeclSyntax(
                    bindingSpecifier: .keyword(.var),
                    bindings: PatternBindingListSyntax([
                        PatternBindingSyntax(
                            pattern: IdentifierPatternSyntax(identifier: .identifier(MockNaming.callCount(MockNaming.subscriptIdentifier(suffix: suffix)))),
                            typeAnnotation: TypeAnnotationSyntax(type: TypeSyntax(stringLiteral: "Int")),
                            initializer: InitializerClauseSyntax(value: IntegerLiteralExprSyntax(literal: .integerLiteral("0")))
                        )
                    ])
                )
                generatedMembers.append(MemberBlockItemSyntax(decl: callCountDecl))

                // SubscriptCallArgs
                let tupleType = Self.buildCallArgsTupleType(parameters: parameters, genericParamNames: genericParamNames)
                let callArgsDecl = VariableDeclSyntax(
                    bindingSpecifier: .keyword(.var),
                    bindings: PatternBindingListSyntax([
                        PatternBindingSyntax(
                            pattern: IdentifierPatternSyntax(identifier: .identifier(MockNaming.callArgs(MockNaming.subscriptIdentifier(suffix: suffix)))),
                            typeAnnotation: TypeAnnotationSyntax(type: ArrayTypeSyntax(element: tupleType)),
                            initializer: InitializerClauseSyntax(value: ArrayExprSyntax(elements: ArrayElementListSyntax([])))
                        )
                    ])
                )
                generatedMembers.append(MemberBlockItemSyntax(decl: callArgsDecl))

                // SubscriptHandler (getter)
                let getterEffects = Self.effectfulSubscriptGetter(subscriptDecl)?.effectSpecifiers
                let closureType = buildSubscriptGetterClosureType(
                    parameters: parameters,
                    returnType: returnType,
                    genericParamNames: genericParamNames,
                    effects: getterEffects
                )

                let handlerDecl = VariableDeclSyntax(
                    bindingSpecifier: .keyword(.var),
                    bindings: PatternBindingListSyntax([
                        PatternBindingSyntax(
                            pattern: IdentifierPatternSyntax(identifier: .identifier(MockNaming.handler(MockNaming.subscriptIdentifier(suffix: suffix)))),
                            typeAnnotation: TypeAnnotationSyntax(
                                type: OptionalTypeSyntax(wrappedType: TypeSyntax(stringLiteral: "(@Sendable \(closureType))"))
                            ),
                            initializer: InitializerClauseSyntax(value: NilLiteralExprSyntax())
                        )
                    ])
                )
                generatedMembers.append(MemberBlockItemSyntax(decl: handlerDecl))

                // SubscriptSetHandler (setter) - only if not get-only
                if !isGetOnly {
                    let setClosureType = buildSubscriptSetterClosureType(
                        parameters: parameters,
                        returnType: returnType,
                        genericParamNames: genericParamNames
                    )

                    let setHandlerDecl = VariableDeclSyntax(
                        bindingSpecifier: .keyword(.var),
                        bindings: PatternBindingListSyntax([
                            PatternBindingSyntax(
                                pattern: IdentifierPatternSyntax(identifier: .identifier(MockNaming.setHandler(MockNaming.subscriptIdentifier(suffix: suffix)))),
                                typeAnnotation: TypeAnnotationSyntax(
                                    type: OptionalTypeSyntax(wrappedType: TypeSyntax(stringLiteral: "(@Sendable \(setClosureType))"))
                                ),
                                initializer: InitializerClauseSyntax(value: NilLiteralExprSyntax())
                            )
                        ])
                    )
                    generatedMembers.append(MemberBlockItemSyntax(decl: setHandlerDecl))
                }
            }

            return generatedMembers
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
