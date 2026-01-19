import SwiftSyntax
import SwiftSyntaxBuilder

struct MockGenerator {
    let protocolName: String
    let mockClassName: String
    let members: MemberBlockItemListSyntax

    func generate() throws -> ClassDeclSyntax {
        var classMembers: [MemberBlockItemSyntax] = []

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

        return ClassDeclSyntax(
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.public))
            ]),
            name: .identifier(mockClassName),
            inheritanceClause: InheritanceClauseSyntax(
                inheritedTypes: InheritedTypeListSyntax([
                    InheritedTypeSyntax(type: TypeSyntax(stringLiteral: protocolName))
                ])
            ),
            memberBlock: memberBlock
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

        // Generate call count property
        let callCountProperty = generateCallCountProperty(funcName: funcName)
        members.append(MemberBlockItemSyntax(decl: callCountProperty))

        // Generate call arguments storage
        let callArgsProperty = generateCallArgsProperty(funcName: funcName, parameters: parameters)
        members.append(MemberBlockItemSyntax(decl: callArgsProperty))

        // Generate handler property
        let handlerProperty = generateHandlerProperty(
            funcName: funcName,
            parameters: parameters,
            returnType: returnType,
            isAsync: isAsync,
            isThrows: isThrows
        )
        members.append(MemberBlockItemSyntax(decl: handlerProperty))

        // Generate the mock function implementation
        let mockFunction = generateMockFunction(funcDecl)
        members.append(MemberBlockItemSyntax(decl: mockFunction))

        return members
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
        parameters: FunctionParameterListSyntax
    ) -> VariableDeclSyntax {
        let tupleType = buildParameterTupleType(parameters: parameters)

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

    private func buildParameterTupleType(parameters: FunctionParameterListSyntax) -> TypeSyntax {
        if parameters.isEmpty {
            return TypeSyntax(TupleTypeSyntax(elements: TupleTypeElementListSyntax([])))
        }

        if parameters.count == 1, let param = parameters.first {
            return param.type
        }

        let tupleElements = parameters.enumerated().map { index, param -> TupleTypeElementSyntax in
            let isLast = index == parameters.count - 1
            return TupleTypeElementSyntax(
                firstName: param.secondName ?? param.firstName,
                colon: .colonToken(),
                type: param.type,
                trailingComma: isLast ? nil : .commaToken()
            )
        }

        return TypeSyntax(TupleTypeSyntax(elements: TupleTypeElementListSyntax(tupleElements)))
    }

    private func generateHandlerProperty(
        funcName: String,
        parameters: FunctionParameterListSyntax,
        returnType: TypeSyntax?,
        isAsync: Bool,
        isThrows: Bool
    ) -> VariableDeclSyntax {
        let paramTupleType = buildParameterTupleType(parameters: parameters)
        let returnTypeStr = returnType?.description ?? "Void"

        var closureType = "(\(paramTupleType.description))"
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

    private func generateMockFunction(_ funcDecl: FunctionDeclSyntax) -> FunctionDeclSyntax {
        let funcName = funcDecl.name.text
        let parameters = funcDecl.signature.parameterClause.parameters
        let returnType = funcDecl.signature.returnClause?.type
        let isAsync = funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil
        let isThrows = funcDecl.signature.effectSpecifiers?.throwsClause != nil

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
            isThrows: isThrows
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
            signature: funcDecl.signature,
            body: body
        )
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
        isThrows: Bool
    ) -> CodeBlockItemSyntax {
        let argsExpr = buildArgsExpression(parameters: parameters)

        var handlerCall: ExprSyntax = ExprSyntax(FunctionCallExprSyntax(
            calledExpression: ForceUnwrapExprSyntax(
                expression: DeclReferenceExprSyntax(baseName: .identifier("\(funcName)Handler"))
            ),
            leftParen: .leftParenToken(),
            arguments: LabeledExprListSyntax([
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
            return CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: """
                guard let handler = \(funcName)Handler else {
                    fatalError("\\(Self.self).\(funcName)Handler is not set")
                }
                return \(isThrows ? "try " : "")\(isAsync ? "await " : "")handler(\(argsExpr))
                """)))
        } else {
            return CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: """
                if let handler = \(funcName)Handler {
                    \(isThrows ? "try " : "")\(isAsync ? "await " : "")handler(\(argsExpr))
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

            if isGetOnly {
                // Generate backing storage
                let storageProperty = generateStorageProperty(varName: varName, varType: varType)
                members.append(MemberBlockItemSyntax(decl: storageProperty))

                // Generate computed property
                let computedProperty = generateComputedGetProperty(
                    varDecl: varDecl,
                    varName: varName,
                    varType: varType
                )
                members.append(MemberBlockItemSyntax(decl: computedProperty))
            } else {
                // Generate simple stored property
                let storedProperty = generateStoredProperty(
                    varDecl: varDecl,
                    varName: varName,
                    varType: varType
                )
                members.append(MemberBlockItemSyntax(decl: storedProperty))
            }
        }

        return members
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

    private func generateStorageProperty(varName: String, varType: TypeSyntax) -> VariableDeclSyntax {
        let isOptional = varType.is(OptionalTypeSyntax.self) ||
                         varType.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)

        let storageType: TypeSyntax
        let initializer: InitializerClauseSyntax?

        if isOptional {
            storageType = varType
            initializer = InitializerClauseSyntax(value: NilLiteralExprSyntax())
        } else {
            storageType = TypeSyntax(OptionalTypeSyntax(wrappedType: varType))
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
                    typeAnnotation: TypeAnnotationSyntax(type: varType),
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
    ) -> VariableDeclSyntax {
        let isOptional = varType.is(OptionalTypeSyntax.self) ||
                         varType.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)

        var initializer: InitializerClauseSyntax?
        if isOptional {
            initializer = InitializerClauseSyntax(value: NilLiteralExprSyntax())
        }

        let storageType: TypeSyntax
        if isOptional {
            storageType = varType
        } else {
            storageType = TypeSyntax(ImplicitlyUnwrappedOptionalTypeSyntax(wrappedType: varType))
        }

        return VariableDeclSyntax(
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.public))
            ]),
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier(varName)),
                    typeAnnotation: TypeAnnotationSyntax(type: storageType),
                    initializer: initializer
                )
            ])
        )
    }
}
