import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Sendable Support

extension MockGenerator {
    func generateStorageStruct() -> StructDeclSyntax {
        var storageMembers: [MemberBlockItemSyntax] = []

        // Group methods by name to detect overloads (including conditional members)
        let methodGroups = groupMethodsByNameIncludingConditional()

        // Extract all members including those in #if blocks
        let conditionalMembers = extractConditionalMembers()

        // Group storage members by their condition
        var unconditionalMembers: [MemberBlockItemSyntax] = []
        var membersByCondition: [String: [MemberBlockItemSyntax]] = [:]
        var conditionExprs: [String: ExprSyntax] = [:]

        for conditionalMember in conditionalMembers {
            var generatedMembers: [MemberBlockItemSyntax] = []

            if let funcDecl = conditionalMember.decl.as(FunctionDeclSyntax.self) {
                let funcName = funcDecl.name.text
                let methodGroup = methodGroups[funcName] ?? []
                let isOverloaded = methodGroup.count > 1
                let suffix = isOverloaded ? Self.functionIdentifierSuffix(from: funcDecl, in: methodGroup) : ""
                let identifier = suffix.isEmpty ? funcName : "\(funcName)\(suffix)"
                let parameters = funcDecl.signature.parameterClause.parameters
                let returnType = funcDecl.signature.returnClause?.type
                let isAsync = funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil
                let isThrows = funcDecl.signature.effectSpecifiers?.hasThrowsEffect ?? false
                let genericParamNames = Self.extractGenericParameterNames(from: funcDecl)

                // CallCount
                let callCountDecl = VariableDeclSyntax(
                    bindingSpecifier: .keyword(.var),
                    bindings: PatternBindingListSyntax([
                        PatternBindingSyntax(
                            pattern: IdentifierPatternSyntax(identifier: .identifier("\(identifier)CallCount")),
                            typeAnnotation: TypeAnnotationSyntax(type: TypeSyntax(stringLiteral: "Int")),
                            initializer: InitializerClauseSyntax(value: IntegerLiteralExprSyntax(literal: .integerLiteral("0")))
                        )
                    ])
                )
                generatedMembers.append(MemberBlockItemSyntax(decl: callCountDecl))

                // CallArgs
                let tupleType = Self.buildParameterTupleType(parameters: parameters, genericParamNames: genericParamNames)
                let callArgsDecl = VariableDeclSyntax(
                    bindingSpecifier: .keyword(.var),
                    bindings: PatternBindingListSyntax([
                        PatternBindingSyntax(
                            pattern: IdentifierPatternSyntax(identifier: .identifier("\(identifier)CallArgs")),
                            typeAnnotation: TypeAnnotationSyntax(type: ArrayTypeSyntax(element: tupleType)),
                            initializer: InitializerClauseSyntax(value: ArrayExprSyntax(elements: ArrayElementListSyntax([])))
                        )
                    ])
                )
                generatedMembers.append(MemberBlockItemSyntax(decl: callArgsDecl))

                // Handler
                let paramTupleType = Self.buildParameterTupleType(
                    parameters: parameters,
                    genericParamNames: genericParamNames
                )
                let erasedReturnType = returnType.map { Self.eraseGenericTypes(in: $0, genericParamNames: genericParamNames) }
                let returnTypeStr = erasedReturnType?.description ?? "Void"

                var closureType = parameters.isEmpty ? "()" : "(\(paramTupleType.description))"
                if isAsync { closureType += " async" }
                if isThrows { closureType += " throws" }
                closureType += " -> \(returnTypeStr)"

                let handlerDecl = VariableDeclSyntax(
                    bindingSpecifier: .keyword(.var),
                    bindings: PatternBindingListSyntax([
                        PatternBindingSyntax(
                            pattern: IdentifierPatternSyntax(identifier: .identifier("\(identifier)Handler")),
                            typeAnnotation: TypeAnnotationSyntax(
                                type: OptionalTypeSyntax(wrappedType: TypeSyntax(stringLiteral: "(@Sendable \(closureType))"))
                            ),
                            initializer: InitializerClauseSyntax(value: NilLiteralExprSyntax())
                        )
                    ])
                )
                generatedMembers.append(MemberBlockItemSyntax(decl: handlerDecl))
            } else if let varDecl = conditionalMember.decl.as(VariableDeclSyntax.self) {
                for binding in varDecl.bindings {
                    guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                          let typeAnnotation = binding.typeAnnotation else { continue }

                    let varName = identifier.identifier.text
                    let varType = typeAnnotation.type
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
                                pattern: IdentifierPatternSyntax(identifier: .identifier("_\(varName)")),
                                typeAnnotation: TypeAnnotationSyntax(type: storageType),
                                initializer: InitializerClauseSyntax(value: NilLiteralExprSyntax())
                            )
                        ])
                    )
                    generatedMembers.append(MemberBlockItemSyntax(decl: storageProp))
                }
            } else if let subscriptDecl = conditionalMember.decl.as(SubscriptDeclSyntax.self) {
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
                            pattern: IdentifierPatternSyntax(identifier: .identifier("subscript\(suffix)CallCount")),
                            typeAnnotation: TypeAnnotationSyntax(type: TypeSyntax(stringLiteral: "Int")),
                            initializer: InitializerClauseSyntax(value: IntegerLiteralExprSyntax(literal: .integerLiteral("0")))
                        )
                    ])
                )
                generatedMembers.append(MemberBlockItemSyntax(decl: callCountDecl))

                // SubscriptCallArgs
                let tupleType = Self.buildParameterTupleType(parameters: parameters, genericParamNames: genericParamNames)
                let callArgsDecl = VariableDeclSyntax(
                    bindingSpecifier: .keyword(.var),
                    bindings: PatternBindingListSyntax([
                        PatternBindingSyntax(
                            pattern: IdentifierPatternSyntax(identifier: .identifier("subscript\(suffix)CallArgs")),
                            typeAnnotation: TypeAnnotationSyntax(type: ArrayTypeSyntax(element: tupleType)),
                            initializer: InitializerClauseSyntax(value: ArrayExprSyntax(elements: ArrayElementListSyntax([])))
                        )
                    ])
                )
                generatedMembers.append(MemberBlockItemSyntax(decl: callArgsDecl))

                // SubscriptHandler (getter)
                let paramTupleType = Self.buildParameterTupleType(
                    parameters: parameters,
                    genericParamNames: genericParamNames
                )
                let erasedReturnType = Self.eraseGenericTypes(in: returnType, genericParamNames: genericParamNames)
                let returnTypeStr = erasedReturnType.description

                let closureType = parameters.isEmpty ? "() -> \(returnTypeStr)" : "(\(paramTupleType.description)) -> \(returnTypeStr)"

                let handlerDecl = VariableDeclSyntax(
                    bindingSpecifier: .keyword(.var),
                    bindings: PatternBindingListSyntax([
                        PatternBindingSyntax(
                            pattern: IdentifierPatternSyntax(identifier: .identifier("subscript\(suffix)Handler")),
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
                    let setClosureType: String
                    if parameters.isEmpty {
                        setClosureType = "(\(returnTypeStr)) -> Void"
                    } else {
                        setClosureType = "(\(paramTupleType.description), \(returnTypeStr)) -> Void"
                    }

                    let setHandlerDecl = VariableDeclSyntax(
                        bindingSpecifier: .keyword(.var),
                        bindings: PatternBindingListSyntax([
                            PatternBindingSyntax(
                                pattern: IdentifierPatternSyntax(identifier: .identifier("subscript\(suffix)SetHandler")),
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

            // Group by condition
            if let condition = conditionalMember.condition {
                let conditionKey = condition.trimmedDescription
                conditionExprs[conditionKey] = condition
                membersByCondition[conditionKey, default: []].append(contentsOf: generatedMembers)
            } else {
                unconditionalMembers.append(contentsOf: generatedMembers)
            }
        }

        // Add unconditional members first
        storageMembers.append(contentsOf: unconditionalMembers)

        // Add conditional members wrapped in their respective #if blocks (sorted for deterministic output)
        for conditionKey in membersByCondition.keys.sorted() {
            guard let members = membersByCondition[conditionKey],
                  let condition = conditionExprs[conditionKey] else {
                continue
            }
            let wrappedMember = Self.wrapInIfConfig(members: members, condition: condition)
            storageMembers.append(wrappedMember)
        }

        return StructDeclSyntax(
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.private))
            ]),
            name: .identifier("Storage"),
            memberBlock: MemberBlockSyntax(
                leftBrace: .leftBraceToken(trailingTrivia: .newline),
                members: MemberBlockItemListSyntax(storageMembers),
                rightBrace: .rightBraceToken(leadingTrivia: .newline)
            )
        )
    }

    func generateMutexProperty(storageStrategy: StorageStrategy) -> VariableDeclSyntax {
        guard let lockType = storageStrategy.lockTypeName else {
            fatalError("generateMutexProperty(storageStrategy:) requires a lock-based strategy")
        }
        return VariableDeclSyntax(
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.private))
            ]),
            bindingSpecifier: .keyword(.let),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier("_storage")),
                    typeAnnotation: nil,
                    initializer: InitializerClauseSyntax(
                        value: FunctionCallExprSyntax(
                            calledExpression: GenericSpecializationExprSyntax(
                                expression: DeclReferenceExprSyntax(baseName: .identifier(lockType)),
                                genericArgumentClause: GenericArgumentClauseSyntax(
                                    arguments: GenericArgumentListSyntax([
                                        makeGenericArgument(type: TypeSyntax(stringLiteral: "Storage"))
                                    ])
                                )
                            ),
                            leftParen: .leftParenToken(),
                            arguments: LabeledExprListSyntax([
                                LabeledExprSyntax(
                                    expression: FunctionCallExprSyntax(
                                        calledExpression: DeclReferenceExprSyntax(baseName: .identifier("Storage")),
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
}
