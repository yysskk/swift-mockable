import SwiftSyntax
import SwiftSyntaxBuilder

struct MockGenerator {
    let protocolName: String
    let mockClassName: String
    let members: MemberBlockItemListSyntax
    let isSendable: Bool

    init(protocolName: String, mockClassName: String, members: MemberBlockItemListSyntax, isSendable: Bool = false) {
        self.protocolName = protocolName
        self.mockClassName = mockClassName
        self.members = members
        self.isSendable = isSendable
    }

    func generate() throws -> ClassDeclSyntax {
        var classMembers: [MemberBlockItemSyntax] = []

        // For Sendable protocols, add a Mutex for thread-safe storage
        if isSendable {
            let storageStruct = generateStorageStruct()
            classMembers.append(MemberBlockItemSyntax(decl: storageStruct))

            let mutexProperty = generateMutexProperty()
            classMembers.append(MemberBlockItemSyntax(decl: mutexProperty))
        }

        // Generate members for each protocol requirement
        for member in members {
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                let funcMembers = generateFunctionMock(funcDecl)
                classMembers.append(contentsOf: funcMembers)
            } else if let varDecl = member.decl.as(VariableDeclSyntax.self) {
                let varMembers = generateVariableMock(varDecl)
                classMembers.append(contentsOf: varMembers)
            }
        }

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
        var modifiers: [DeclModifierSyntax] = [
            DeclModifierSyntax(name: .keyword(.public))
        ]
        if isSendable {
            modifiers.append(DeclModifierSyntax(name: .keyword(.final)))
        }

        // Build attributes
        var attributes: [AttributeListSyntax.Element] = []
        if isSendable {
            // Add @available attribute for Mutex which requires macOS 15.0+
            let availableAttribute: AttributeSyntax = "@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)"
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

    // MARK: - Sendable Support

    private func generateStorageStruct() -> StructDeclSyntax {
        var storageMembers: [MemberBlockItemSyntax] = []

        for member in members {
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                let funcName = funcDecl.name.text
                let parameters = funcDecl.signature.parameterClause.parameters
                let returnType = funcDecl.signature.returnClause?.type
                let isAsync = funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil
                let isThrows = funcDecl.signature.effectSpecifiers?.throwsClause != nil
                let genericParamNames = extractGenericParameterNames(from: funcDecl)

                // CallCount
                let callCountDecl = VariableDeclSyntax(
                    bindingSpecifier: .keyword(.var),
                    bindings: PatternBindingListSyntax([
                        PatternBindingSyntax(
                            pattern: IdentifierPatternSyntax(identifier: .identifier("\(funcName)CallCount")),
                            typeAnnotation: TypeAnnotationSyntax(type: TypeSyntax(stringLiteral: "Int")),
                            initializer: InitializerClauseSyntax(value: IntegerLiteralExprSyntax(literal: .integerLiteral("0")))
                        )
                    ])
                )
                storageMembers.append(MemberBlockItemSyntax(decl: callCountDecl))

                // CallArgs
                let tupleType = buildParameterTupleType(parameters: parameters, genericParamNames: genericParamNames)
                let callArgsDecl = VariableDeclSyntax(
                    bindingSpecifier: .keyword(.var),
                    bindings: PatternBindingListSyntax([
                        PatternBindingSyntax(
                            pattern: IdentifierPatternSyntax(identifier: .identifier("\(funcName)CallArgs")),
                            typeAnnotation: TypeAnnotationSyntax(type: ArrayTypeSyntax(element: tupleType)),
                            initializer: InitializerClauseSyntax(value: ArrayExprSyntax(elements: ArrayElementListSyntax([])))
                        )
                    ])
                )
                storageMembers.append(MemberBlockItemSyntax(decl: callArgsDecl))

                // Handler
                let paramTupleType = buildParameterTupleType(parameters: parameters, genericParamNames: genericParamNames, forHandler: true)
                let erasedReturnType = returnType.map { eraseGenericTypes(in: $0, genericParamNames: genericParamNames) }
                let returnTypeStr = erasedReturnType?.description ?? "Void"

                var closureType = parameters.isEmpty ? "()" : "(\(paramTupleType.description))"
                if isAsync { closureType += " async" }
                if isThrows { closureType += " throws" }
                closureType += " -> \(returnTypeStr)"

                let handlerDecl = VariableDeclSyntax(
                    bindingSpecifier: .keyword(.var),
                    bindings: PatternBindingListSyntax([
                        PatternBindingSyntax(
                            pattern: IdentifierPatternSyntax(identifier: .identifier("\(funcName)Handler")),
                            typeAnnotation: TypeAnnotationSyntax(
                                type: OptionalTypeSyntax(wrappedType: TypeSyntax(stringLiteral: "(@Sendable \(closureType))"))
                            ),
                            initializer: InitializerClauseSyntax(value: NilLiteralExprSyntax())
                        )
                    ])
                )
                storageMembers.append(MemberBlockItemSyntax(decl: handlerDecl))
            } else if let varDecl = member.decl.as(VariableDeclSyntax.self) {
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
                    storageMembers.append(MemberBlockItemSyntax(decl: storageProp))
                }
            }
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

    private func generateMutexProperty() -> VariableDeclSyntax {
        VariableDeclSyntax(
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
                                expression: DeclReferenceExprSyntax(baseName: .identifier("Mutex")),
                                genericArgumentClause: GenericArgumentClauseSyntax(
                                    arguments: GenericArgumentListSyntax([
                                        GenericArgumentSyntax(argument: .type(TypeSyntax(stringLiteral: "Storage")))
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

    // MARK: - Function Mock Generation

    private func generateFunctionMock(_ funcDecl: FunctionDeclSyntax) -> [MemberBlockItemSyntax] {
        var members: [MemberBlockItemSyntax] = []

        let funcName = funcDecl.name.text
        let parameters = funcDecl.signature.parameterClause.parameters
        let returnType = funcDecl.signature.returnClause?.type
        let isAsync = funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil
        let isThrows = funcDecl.signature.effectSpecifiers?.throwsClause != nil
        let genericParamNames = extractGenericParameterNames(from: funcDecl)

        if isSendable {
            // For Sendable protocols, generate computed properties that access the Mutex
            let callCountProperty = generateSendableCallCountProperty(funcName: funcName)
            members.append(MemberBlockItemSyntax(decl: callCountProperty))

            let callArgsProperty = generateSendableCallArgsProperty(
                funcName: funcName,
                parameters: parameters,
                genericParamNames: genericParamNames
            )
            members.append(MemberBlockItemSyntax(decl: callArgsProperty))

            let handlerProperty = generateSendableHandlerProperty(
                funcName: funcName,
                parameters: parameters,
                returnType: returnType,
                isAsync: isAsync,
                isThrows: isThrows,
                genericParamNames: genericParamNames
            )
            members.append(MemberBlockItemSyntax(decl: handlerProperty))

            let mockFunction = generateSendableMockFunction(funcDecl, genericParamNames: genericParamNames)
            members.append(MemberBlockItemSyntax(decl: mockFunction))
        } else {
            // Generate call count property
            let callCountProperty = generateCallCountProperty(funcName: funcName)
            members.append(MemberBlockItemSyntax(decl: callCountProperty))

            // Generate call arguments storage
            let callArgsProperty = generateCallArgsProperty(
                funcName: funcName,
                parameters: parameters,
                genericParamNames: genericParamNames
            )
            members.append(MemberBlockItemSyntax(decl: callArgsProperty))

            // Generate handler property
            let handlerProperty = generateHandlerProperty(
                funcName: funcName,
                parameters: parameters,
                returnType: returnType,
                isAsync: isAsync,
                isThrows: isThrows,
                genericParamNames: genericParamNames
            )
            members.append(MemberBlockItemSyntax(decl: handlerProperty))

            // Generate the mock function implementation
            let mockFunction = generateMockFunction(funcDecl, genericParamNames: genericParamNames)
            members.append(MemberBlockItemSyntax(decl: mockFunction))
        }

        return members
    }

    // MARK: - Sendable Function Mock Generation

    private func generateSendableCallCountProperty(funcName: String) -> VariableDeclSyntax {
        VariableDeclSyntax(
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.public))
            ]),
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier("\(funcName)CallCount")),
                    typeAnnotation: TypeAnnotationSyntax(type: TypeSyntax(stringLiteral: "Int")),
                    accessorBlock: AccessorBlockSyntax(
                        accessors: .accessors(AccessorDeclListSyntax([
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.get),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.\(funcName)CallCount }")))
                                    ])
                                )
                            ),
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.set),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.\(funcName)CallCount = newValue }")))
                                    ])
                                )
                            )
                        ]))
                    )
                )
            ])
        )
    }

    private func generateSendableCallArgsProperty(
        funcName: String,
        parameters: FunctionParameterListSyntax,
        genericParamNames: Set<String>
    ) -> VariableDeclSyntax {
        let tupleType = buildParameterTupleType(parameters: parameters, genericParamNames: genericParamNames)

        return VariableDeclSyntax(
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.public))
            ]),
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier("\(funcName)CallArgs")),
                    typeAnnotation: TypeAnnotationSyntax(type: ArrayTypeSyntax(element: tupleType)),
                    accessorBlock: AccessorBlockSyntax(
                        accessors: .accessors(AccessorDeclListSyntax([
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.get),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.\(funcName)CallArgs }")))
                                    ])
                                )
                            ),
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.set),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.\(funcName)CallArgs = newValue }")))
                                    ])
                                )
                            )
                        ]))
                    )
                )
            ])
        )
    }

    private func generateSendableHandlerProperty(
        funcName: String,
        parameters: FunctionParameterListSyntax,
        returnType: TypeSyntax?,
        isAsync: Bool,
        isThrows: Bool,
        genericParamNames: Set<String>
    ) -> VariableDeclSyntax {
        let paramTupleType = buildParameterTupleType(parameters: parameters, genericParamNames: genericParamNames, forHandler: true)
        let erasedReturnType = returnType.map { eraseGenericTypes(in: $0, genericParamNames: genericParamNames) }
        let returnTypeStr = erasedReturnType?.description ?? "Void"

        var closureType = parameters.isEmpty ? "()" : "(\(paramTupleType.description))"
        if isAsync { closureType += " async" }
        if isThrows { closureType += " throws" }
        closureType += " -> \(returnTypeStr)"

        let handlerType = "(@Sendable \(closureType))?"

        return VariableDeclSyntax(
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.public))
            ]),
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier("\(funcName)Handler")),
                    typeAnnotation: TypeAnnotationSyntax(type: TypeSyntax(stringLiteral: handlerType)),
                    accessorBlock: AccessorBlockSyntax(
                        accessors: .accessors(AccessorDeclListSyntax([
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.get),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.\(funcName)Handler }")))
                                    ])
                                )
                            ),
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.set),
                                body: CodeBlockSyntax(
                                    statements: CodeBlockItemListSyntax([
                                        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_storage.withLock { $0.\(funcName)Handler = newValue }")))
                                    ])
                                )
                            )
                        ]))
                    )
                )
            ])
        )
    }

    private func generateSendableMockFunction(_ funcDecl: FunctionDeclSyntax, genericParamNames: Set<String>) -> FunctionDeclSyntax {
        let funcName = funcDecl.name.text
        let parameters = funcDecl.signature.parameterClause.parameters
        let returnType = funcDecl.signature.returnClause?.type
        let isAsync = funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil
        let isThrows = funcDecl.signature.effectSpecifiers?.throwsClause != nil
        let hasGenericReturn = returnType.map { typeContainsGeneric($0, genericParamNames: genericParamNames) } ?? false

        let argsExpr = buildArgsExpression(parameters: parameters)
        let hasReturnValue = returnType != nil && returnType?.description != "Void"
        let handlerCallArgs = parameters.isEmpty ? "" : "\(argsExpr)"

        // Build the function body using withLock for thread safety
        let bodyCode: String
        if hasReturnValue {
            let returnTypeStr = returnType?.description ?? "Void"
            let castSuffix = hasGenericReturn ? " as! \(returnTypeStr)" : ""
            bodyCode = """
                let handler = _storage.withLock { storage -> (@Sendable \(buildClosureType(parameters: parameters, returnType: returnType, isAsync: isAsync, isThrows: isThrows, genericParamNames: genericParamNames)))? in
                    storage.\(funcName)CallCount += 1
                    storage.\(funcName)CallArgs.append(\(argsExpr))
                    return storage.\(funcName)Handler
                }
                guard let handler else {
                    fatalError("\\(Self.self).\(funcName)Handler is not set")
                }
                return \(isThrows ? "try " : "")\(isAsync ? "await " : "")handler(\(handlerCallArgs))\(castSuffix)
                """
        } else {
            bodyCode = """
                let handler = _storage.withLock { storage -> (@Sendable \(buildClosureType(parameters: parameters, returnType: returnType, isAsync: isAsync, isThrows: isThrows, genericParamNames: genericParamNames)))? in
                    storage.\(funcName)CallCount += 1
                    storage.\(funcName)CallArgs.append(\(argsExpr))
                    return storage.\(funcName)Handler
                }
                if let handler {
                    \(isThrows ? "try " : "")\(isAsync ? "await " : "")handler(\(handlerCallArgs))
                }
                """
        }

        let body = CodeBlockSyntax(
            leftBrace: .leftBraceToken(trailingTrivia: .newline),
            statements: CodeBlockItemListSyntax([
                CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: bodyCode)))
            ]),
            rightBrace: .rightBraceToken(leadingTrivia: .newline)
        )

        return FunctionDeclSyntax(
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.public))
            ]),
            name: funcDecl.name,
            genericParameterClause: funcDecl.genericParameterClause,
            signature: funcDecl.signature,
            genericWhereClause: funcDecl.genericWhereClause,
            body: body
        )
    }

    private func buildClosureType(
        parameters: FunctionParameterListSyntax,
        returnType: TypeSyntax?,
        isAsync: Bool,
        isThrows: Bool,
        genericParamNames: Set<String>
    ) -> String {
        let paramTupleType = buildParameterTupleType(parameters: parameters, genericParamNames: genericParamNames, forHandler: true)
        let erasedReturnType = returnType.map { eraseGenericTypes(in: $0, genericParamNames: genericParamNames) }
        let returnTypeStr = erasedReturnType?.description ?? "Void"

        var closureType = parameters.isEmpty ? "()" : "(\(paramTupleType.description))"
        if isAsync { closureType += " async" }
        if isThrows { closureType += " throws" }
        closureType += " -> \(returnTypeStr)"
        return closureType
    }

    private func extractGenericParameterNames(from funcDecl: FunctionDeclSyntax) -> Set<String> {
        guard let genericClause = funcDecl.genericParameterClause else {
            return []
        }
        return Set(genericClause.parameters.map { $0.name.text })
    }

    private func generateCallCountProperty(funcName: String) -> VariableDeclSyntax {
        VariableDeclSyntax(
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.public))
            ]),
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier("\(funcName)CallCount")),
                    typeAnnotation: TypeAnnotationSyntax(type: TypeSyntax(stringLiteral: "Int")),
                    initializer: InitializerClauseSyntax(value: IntegerLiteralExprSyntax(literal: .integerLiteral("0")))
                )
            ])
        )
    }

    private func generateCallArgsProperty(
        funcName: String,
        parameters: FunctionParameterListSyntax,
        genericParamNames: Set<String>
    ) -> VariableDeclSyntax {
        let tupleType = buildParameterTupleType(parameters: parameters, genericParamNames: genericParamNames)

        return VariableDeclSyntax(
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.public))
            ]),
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier("\(funcName)CallArgs")),
                    typeAnnotation: TypeAnnotationSyntax(
                        type: ArrayTypeSyntax(element: tupleType)
                    ),
                    initializer: InitializerClauseSyntax(
                        value: ArrayExprSyntax(elements: ArrayElementListSyntax([]))
                    )
                )
            ])
        )
    }

    private func buildParameterTupleType(
        parameters: FunctionParameterListSyntax,
        genericParamNames: Set<String> = [],
        forHandler: Bool = false
    ) -> TypeSyntax {
        if parameters.isEmpty {
            // For handler closures, return Void so the closure can be written as { true } instead of { _ in true }
            if forHandler {
                return TypeSyntax(IdentifierTypeSyntax(name: .identifier("Void")))
            }
            return TypeSyntax(TupleTypeSyntax(elements: TupleTypeElementListSyntax([])))
        }

        if parameters.count == 1, let param = parameters.first {
            return eraseGenericTypes(in: param.type, genericParamNames: genericParamNames)
        }

        let tupleElements = parameters.enumerated().map { index, param -> TupleTypeElementSyntax in
            let isLast = index == parameters.count - 1
            let erasedType = eraseGenericTypes(in: param.type, genericParamNames: genericParamNames)
            return TupleTypeElementSyntax(
                firstName: param.secondName ?? param.firstName,
                colon: .colonToken(),
                type: erasedType,
                trailingComma: isLast ? nil : .commaToken()
            )
        }

        return TypeSyntax(TupleTypeSyntax(elements: TupleTypeElementListSyntax(tupleElements)))
    }

    private func eraseGenericTypes(in type: TypeSyntax, genericParamNames: Set<String>) -> TypeSyntax {
        if genericParamNames.isEmpty {
            return type
        }

        // Check if type itself is a generic parameter
        if let identifierType = type.as(IdentifierTypeSyntax.self) {
            if genericParamNames.contains(identifierType.name.text) {
                return TypeSyntax(stringLiteral: "Any")
            }
            // Check for generic arguments like UserDefaultsKey<T>
            if let genericArgs = identifierType.genericArgumentClause {
                let hasGenericParam = genericArgs.arguments.contains { arg in
                    switch arg.argument {
                    case .type(let typeSyntax):
                        if let innerIdent = typeSyntax.as(IdentifierTypeSyntax.self) {
                            return genericParamNames.contains(innerIdent.name.text)
                        }
                        return false
                    case .expr:
                        return false
                    }
                }
                if hasGenericParam {
                    return TypeSyntax(stringLiteral: "Any")
                }
            }
        }

        // Handle optional types
        if let optionalType = type.as(OptionalTypeSyntax.self) {
            let erasedWrapped = eraseGenericTypes(in: optionalType.wrappedType, genericParamNames: genericParamNames)
            if erasedWrapped.description != optionalType.wrappedType.description {
                return TypeSyntax(OptionalTypeSyntax(wrappedType: erasedWrapped))
            }
        }

        // Handle implicitly unwrapped optional types
        if let implicitOptional = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            let erasedWrapped = eraseGenericTypes(in: implicitOptional.wrappedType, genericParamNames: genericParamNames)
            if erasedWrapped.description != implicitOptional.wrappedType.description {
                return TypeSyntax(ImplicitlyUnwrappedOptionalTypeSyntax(wrappedType: erasedWrapped))
            }
        }

        // Handle array types
        if let arrayType = type.as(ArrayTypeSyntax.self) {
            let erasedElement = eraseGenericTypes(in: arrayType.element, genericParamNames: genericParamNames)
            if erasedElement.description != arrayType.element.description {
                return TypeSyntax(ArrayTypeSyntax(element: erasedElement))
            }
        }

        return type
    }

    private func generateHandlerProperty(
        funcName: String,
        parameters: FunctionParameterListSyntax,
        returnType: TypeSyntax?,
        isAsync: Bool,
        isThrows: Bool,
        genericParamNames: Set<String>
    ) -> VariableDeclSyntax {
        let paramTupleType = buildParameterTupleType(parameters: parameters, genericParamNames: genericParamNames, forHandler: true)
        let erasedReturnType = returnType.map { eraseGenericTypes(in: $0, genericParamNames: genericParamNames) }
        let returnTypeStr = erasedReturnType?.description ?? "Void"

        var closureType = parameters.isEmpty ? "()" : "(\(paramTupleType.description))"
        if isAsync {
            closureType += " async"
        }
        if isThrows {
            closureType += " throws"
        }
        closureType += " -> \(returnTypeStr)"

        return VariableDeclSyntax(
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.public))
            ]),
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier("\(funcName)Handler")),
                    typeAnnotation: TypeAnnotationSyntax(
                        type: OptionalTypeSyntax(wrappedType: TypeSyntax(stringLiteral: "(@Sendable \(closureType))"))
                    ),
                    initializer: InitializerClauseSyntax(value: NilLiteralExprSyntax())
                )
            ])
        )
    }

    private func generateMockFunction(_ funcDecl: FunctionDeclSyntax, genericParamNames: Set<String>) -> FunctionDeclSyntax {
        let funcName = funcDecl.name.text
        let parameters = funcDecl.signature.parameterClause.parameters
        let returnType = funcDecl.signature.returnClause?.type
        let isAsync = funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil
        let isThrows = funcDecl.signature.effectSpecifiers?.throwsClause != nil
        let hasGenericReturn = returnType.map { typeContainsGeneric($0, genericParamNames: genericParamNames) } ?? false

        // Build function body
        var statements: [CodeBlockItemSyntax] = []

        // Increment call count
        let incrementStmt = InfixOperatorExprSyntax(
            leftOperand: DeclReferenceExprSyntax(baseName: .identifier("\(funcName)CallCount")),
            operator: BinaryOperatorExprSyntax(operator: .binaryOperator("+=")),
            rightOperand: IntegerLiteralExprSyntax(literal: .integerLiteral("1"))
        )
        statements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(incrementStmt))))

        // Record call arguments
        let argsExpr = buildArgsExpression(parameters: parameters)
        let appendExpr = FunctionCallExprSyntax(
            calledExpression: MemberAccessExprSyntax(
                base: DeclReferenceExprSyntax(baseName: .identifier("\(funcName)CallArgs")),
                name: .identifier("append")
            ),
            leftParen: .leftParenToken(),
            arguments: LabeledExprListSyntax([
                LabeledExprSyntax(expression: argsExpr)
            ]),
            rightParen: .rightParenToken()
        )
        statements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(appendExpr))))

        // Call handler if set
        let handlerCallExpr = buildHandlerCallExpression(
            funcName: funcName,
            parameters: parameters,
            returnType: returnType,
            isAsync: isAsync,
            isThrows: isThrows,
            hasGenericReturn: hasGenericReturn
        )
        statements.append(handlerCallExpr)

        let body = CodeBlockSyntax(
            leftBrace: .leftBraceToken(trailingTrivia: .newline),
            statements: CodeBlockItemListSyntax(statements),
            rightBrace: .rightBraceToken(leadingTrivia: .newline)
        )

        return FunctionDeclSyntax(
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.public))
            ]),
            name: funcDecl.name,
            genericParameterClause: funcDecl.genericParameterClause,
            signature: funcDecl.signature,
            genericWhereClause: funcDecl.genericWhereClause,
            body: body
        )
    }

    private func typeContainsGeneric(_ type: TypeSyntax, genericParamNames: Set<String>) -> Bool {
        if genericParamNames.isEmpty {
            return false
        }

        if let identifierType = type.as(IdentifierTypeSyntax.self) {
            if genericParamNames.contains(identifierType.name.text) {
                return true
            }
            if let genericArgs = identifierType.genericArgumentClause {
                return genericArgs.arguments.contains { arg in
                    switch arg.argument {
                    case .type(let typeSyntax):
                        return typeContainsGeneric(typeSyntax, genericParamNames: genericParamNames)
                    case .expr:
                        return false
                    }
                }
            }
        }

        if let optionalType = type.as(OptionalTypeSyntax.self) {
            return typeContainsGeneric(optionalType.wrappedType, genericParamNames: genericParamNames)
        }

        if let arrayType = type.as(ArrayTypeSyntax.self) {
            return typeContainsGeneric(arrayType.element, genericParamNames: genericParamNames)
        }

        return false
    }

    private func buildArgsExpression(parameters: FunctionParameterListSyntax) -> ExprSyntax {
        if parameters.isEmpty {
            return ExprSyntax(TupleExprSyntax(elements: LabeledExprListSyntax([])))
        }

        if parameters.count == 1, let param = parameters.first {
            let paramName = (param.secondName ?? param.firstName).text
            return ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier(paramName)))
        }

        let tupleElements = parameters.enumerated().map { index, param -> LabeledExprSyntax in
            let paramName = (param.secondName ?? param.firstName).text
            let isLast = index == parameters.count - 1
            return LabeledExprSyntax(
                label: param.secondName ?? param.firstName,
                colon: .colonToken(),
                expression: DeclReferenceExprSyntax(baseName: .identifier(paramName)),
                trailingComma: isLast ? nil : .commaToken()
            )
        }

        return ExprSyntax(TupleExprSyntax(elements: LabeledExprListSyntax(tupleElements)))
    }

    private func buildHandlerCallExpression(
        funcName: String,
        parameters: FunctionParameterListSyntax,
        returnType: TypeSyntax?,
        isAsync: Bool,
        isThrows: Bool,
        hasGenericReturn: Bool = false
    ) -> CodeBlockItemSyntax {
        let argsExpr = buildArgsExpression(parameters: parameters)
        let handlerCallArgs = parameters.isEmpty ? "" : "\(argsExpr)"

        var handlerCall: ExprSyntax = ExprSyntax(FunctionCallExprSyntax(
            calledExpression: ForceUnwrapExprSyntax(
                expression: DeclReferenceExprSyntax(baseName: .identifier("\(funcName)Handler"))
            ),
            leftParen: .leftParenToken(),
            arguments: parameters.isEmpty ? LabeledExprListSyntax([]) : LabeledExprListSyntax([
                LabeledExprSyntax(expression: argsExpr)
            ]),
            rightParen: .rightParenToken()
        ))

        if isThrows {
            handlerCall = ExprSyntax(TryExprSyntax(expression: handlerCall))
        }
        if isAsync {
            handlerCall = ExprSyntax(AwaitExprSyntax(expression: handlerCall))
        }

        let hasReturnValue = returnType != nil && returnType?.description != "Void"

        if hasReturnValue {
            let returnTypeStr = returnType?.description ?? "Void"
            let castSuffix = hasGenericReturn ? " as! \(returnTypeStr)" : ""
            return CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: """
                guard let handler = \(funcName)Handler else {
                    fatalError("\\(Self.self).\(funcName)Handler is not set")
                }
                return \(isThrows ? "try " : "")\(isAsync ? "await " : "")handler(\(handlerCallArgs))\(castSuffix)
                """)))
        } else {
            return CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: """
                if let handler = \(funcName)Handler {
                    \(isThrows ? "try " : "")\(isAsync ? "await " : "")handler(\(handlerCallArgs))
                }
                """)))
        }
    }

    // MARK: - Variable Mock Generation

    private func generateVariableMock(_ varDecl: VariableDeclSyntax) -> [MemberBlockItemSyntax] {
        var members: [MemberBlockItemSyntax] = []

        for binding in varDecl.bindings {
            guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                  let typeAnnotation = binding.typeAnnotation
            else {
                continue
            }

            let varName = identifier.identifier.text
            let varType = typeAnnotation.type

            // Check if it's a get-only property
            let isGetOnly = isGetOnlyProperty(binding: binding)

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

    private func generateSendableBackingSetterProperty(
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

    private func generateSendableVariableProperty(
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

    private func isGetOnlyProperty(binding: PatternBindingSyntax) -> Bool {
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
