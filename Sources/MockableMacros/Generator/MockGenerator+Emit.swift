import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Shared Property and Statement Emitters

extension MockGenerator {
    /// Builds a stored property `var name: Type = initializer` with the given modifiers.
    static func makeStoredProperty(
        modifiers: DeclModifierListSyntax = DeclModifierListSyntax([]),
        name: String,
        type: TypeSyntax,
        initializer: ExprSyntax
    ) -> VariableDeclSyntax {
        VariableDeclSyntax(
            modifiers: modifiers,
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier(name)),
                    typeAnnotation: TypeAnnotationSyntax(type: type),
                    initializer: InitializerClauseSyntax(value: initializer)
                )
            ])
        )
    }

    /// Builds a computed property with one-line `get` and `set` bodies.
    static func makeGetSetProperty(
        modifiers: DeclModifierListSyntax,
        name: String,
        type: TypeSyntax,
        getterBody: String,
        setterBody: String
    ) -> VariableDeclSyntax {
        VariableDeclSyntax(
            modifiers: modifiers,
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier(name)),
                    typeAnnotation: TypeAnnotationSyntax(type: type),
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

    /// Builds a get-only computed property with a one-line getter body.
    static func makeGetOnlyProperty(
        modifiers: DeclModifierListSyntax,
        name: String,
        type: TypeSyntax,
        getterBody: String
    ) -> VariableDeclSyntax {
        VariableDeclSyntax(
            modifiers: modifiers,
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier(name)),
                    typeAnnotation: TypeAnnotationSyntax(type: type),
                    accessorBlock: AccessorBlockSyntax(
                        accessors: .getter(CodeBlockItemListSyntax([
                            CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: getterBody)))
                        ]))
                    )
                )
            ])
        )
    }

    /// Builds a computed property whose accessors read and write `storedName` inside
    /// the `storageName` lock, e.g. `_storage.withLock { $0.fetchCallCount }`.
    static func makeLockBackedProperty(
        modifiers: DeclModifierListSyntax,
        name: String,
        type: TypeSyntax,
        storageName: String,
        storedName: String
    ) -> VariableDeclSyntax {
        makeGetSetProperty(
            modifiers: modifiers,
            name: name,
            type: type,
            getterBody: "\(storageName).withLock { $0.\(storedName) }",
            setterBody: "\(storageName).withLock { $0.\(storedName) = newValue }"
        )
    }

    /// The `else` body of the unset-handler guard: the return type's natural empty
    /// default when it has one, otherwise a `fatalError` naming the unset handler.
    static func unsetHandlerElseBody(returnType: TypeSyntax?, handlerName: String) -> String {
        defaultReturnStatement(for: returnType)
            ?? "fatalError(\"\\(Self.self).\(handlerName) is not set\")"
    }

    /// Builds the unset-handler guard. `binding` is `"_handler"` when the handler was
    /// already bound (the lock path) or `"_handler = fooHandler"` to bind it from the
    /// stored property (the direct path).
    static func makeUnsetHandlerGuard(
        binding: String,
        elseBody: String,
        leadingTrivia: Trivia? = nil
    ) -> CodeBlockItemSyntax {
        CodeBlockItemSyntax(leadingTrivia: leadingTrivia, item: .stmt(StmtSyntax(stringLiteral: """
        guard let \(binding) else {
            \(elseBody)
        }
        """)))
    }

    /// Builds `return <invokePrefix>_handler(<handlerCallArgs>)<castSuffix>`, wrapped
    /// in the typed-throws conversion when `errorType` is set.
    static func makeHandlerReturnStatement(
        invokePrefix: String,
        handlerCallArgs: String,
        castSuffix: String = "",
        errorType: String?,
        leadingTrivia: Trivia? = nil
    ) -> CodeBlockItemSyntax {
        let returnLine = "return \(invokePrefix)_handler(\(handlerCallArgs))\(castSuffix)"
        let item = errorType.map { buildTypedThrowsCatch(innerLines: [returnLine], errorType: $0) }
            ?? CodeBlockItemSyntax(item: .stmt(StmtSyntax(stringLiteral: returnLine)))
        return CodeBlockItemSyntax(leadingTrivia: leadingTrivia, item: item.item)
    }

    /// Builds the two statements that record a call on the direct (non-lock) path:
    /// `<identifier>CallCount += 1` and `<identifier>CallArgs.append(...)`.
    static func makeCallRecordingStatements(
        identifier: String,
        parameters: FunctionParameterListSyntax
    ) -> [CodeBlockItemSyntax] {
        let incrementStmt = InfixOperatorExprSyntax(
            leftOperand: DeclReferenceExprSyntax(baseName: .identifier(MockNaming.callCount(identifier))),
            operator: BinaryOperatorExprSyntax(operator: .binaryOperator("+=")),
            rightOperand: IntegerLiteralExprSyntax(literal: .integerLiteral("1"))
        )

        let appendExpr = FunctionCallExprSyntax(
            calledExpression: MemberAccessExprSyntax(
                base: DeclReferenceExprSyntax(baseName: .identifier(MockNaming.callArgs(identifier))),
                name: .identifier("append")
            ),
            leftParen: .leftParenToken(),
            arguments: LabeledExprListSyntax([
                LabeledExprSyntax(expression: buildCallArgsExpression(parameters: parameters))
            ]),
            rightParen: .rightParenToken()
        )

        return [
            CodeBlockItemSyntax(item: .expr(ExprSyntax(incrementStmt))),
            CodeBlockItemSyntax(item: .expr(ExprSyntax(appendExpr)))
        ]
    }
}
