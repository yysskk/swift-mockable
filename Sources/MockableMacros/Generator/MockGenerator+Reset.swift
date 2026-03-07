import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Reset Method Generation

extension MockGenerator {
    func generateResetMethod() -> FunctionDeclSyntax {
        if isSendable || isActor {
            return generateSendableResetMethod()
        } else {
            return generateRegularResetMethod()
        }
    }

    private func generateRegularResetMethod() -> FunctionDeclSyntax {
        var statements: [CodeBlockItemSyntax] = []

        // Group methods by name to detect overloads (including conditional members)
        let methodGroups = groupMethodsByNameIncludingConditional()

        let resetStatements = mapCodeBlockItemsPreservingIfConfig { decl in
            var generatedStatements: [CodeBlockItemSyntax] = []

            if let funcDecl = decl.as(FunctionDeclSyntax.self) {
                let funcName = funcDecl.name.text
                let methodGroup = methodGroups[funcName] ?? []
                let isOverloaded = methodGroup.count > 1
                let suffix = isOverloaded ? Self.functionIdentifierSuffix(from: funcDecl, in: methodGroup) : ""
                let identifier = suffix.isEmpty ? funcName : "\(funcName)\(suffix)"

                // Reset call count
                generatedStatements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "\(identifier)CallCount = 0"))))

                // Reset call args
                generatedStatements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "\(identifier)CallArgs = []"))))

                // Reset handler
                generatedStatements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "\(identifier)Handler = nil"))))
            } else if let varDecl = decl.as(VariableDeclSyntax.self) {
                for binding in varDecl.bindings {
                    guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                          let typeAnnotation = binding.typeAnnotation else { continue }

                    let varName = identifier.identifier.text
                    let varType = typeAnnotation.type
                    let isOptional = varType.is(OptionalTypeSyntax.self) || varType.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)
                    let isGetOnly = Self.isGetOnlyProperty(binding: binding)

                    // For get-only properties, always use _varName
                    // For get-set properties:
                    //   - Optional types use varName directly (no backing storage)
                    //   - Non-optional types use _varName backing storage
                    if isGetOnly || !isOptional {
                        generatedStatements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_\(varName) = nil"))))
                    } else {
                        generatedStatements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "\(varName) = nil"))))
                    }
                }
            } else if let subscriptDecl = decl.as(SubscriptDeclSyntax.self) {
                let isGetOnly = Self.isGetOnlySubscript(subscriptDecl)
                let suffix = Self.subscriptIdentifierSuffix(from: subscriptDecl)

                // Reset subscript call count
                generatedStatements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "subscript\(suffix)CallCount = 0"))))

                // Reset subscript call args
                generatedStatements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "subscript\(suffix)CallArgs = []"))))

                // Reset subscript handler
                generatedStatements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "subscript\(suffix)Handler = nil"))))

                // Reset subscript set handler if not get-only
                if !isGetOnly {
                    generatedStatements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "subscript\(suffix)SetHandler = nil"))))
                }
            }

            return generatedStatements
        }

        // Add super.resetMock() call if inheriting from parent mock
        if hasParentMock {
            statements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "super.resetMock()"))))
        }

        statements.append(contentsOf: resetStatements)

        let body = CodeBlockSyntax(
            leftBrace: .leftBraceToken(trailingTrivia: .newline),
            statements: CodeBlockItemListSyntax(statements),
            rightBrace: .rightBraceToken(leadingTrivia: .newline)
        )

        let additionalModifiers: [DeclModifierSyntax] = hasParentMock
            ? [DeclModifierSyntax(name: .keyword(.override))]
            : []

        return FunctionDeclSyntax(
            modifiers: buildModifiers(additional: additionalModifiers),
            name: .identifier("resetMock"),
            signature: FunctionSignatureSyntax(
                parameterClause: FunctionParameterClauseSyntax(
                    leftParen: .leftParenToken(),
                    parameters: FunctionParameterListSyntax([]),
                    rightParen: .rightParenToken()
                )
            ),
            body: body
        )
    }

    private func generateSendableResetMethod() -> FunctionDeclSyntax {
        // Group methods by name to detect overloads (including conditional members)
        let methodGroups = groupMethodsByNameIncludingConditional()

        let resetLines = mapLinesPreservingIfConfig { decl in
            var generatedStatements: [String] = []

            if let funcDecl = decl.as(FunctionDeclSyntax.self) {
                let funcName = funcDecl.name.text
                let methodGroup = methodGroups[funcName] ?? []
                let isOverloaded = methodGroup.count > 1
                let suffix = isOverloaded ? Self.functionIdentifierSuffix(from: funcDecl, in: methodGroup) : ""
                let identifier = suffix.isEmpty ? funcName : "\(funcName)\(suffix)"

                // Reset call count
                generatedStatements.append("storage.\(identifier)CallCount = 0")

                // Reset call args
                generatedStatements.append("storage.\(identifier)CallArgs = []")

                // Reset handler
                generatedStatements.append("storage.\(identifier)Handler = nil")
            } else if let varDecl = decl.as(VariableDeclSyntax.self) {
                for binding in varDecl.bindings {
                    guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
                    let varName = identifier.identifier.text

                    // Reset variable backing storage
                    generatedStatements.append("storage._\(varName) = nil")
                }
            } else if let subscriptDecl = decl.as(SubscriptDeclSyntax.self) {
                let isGetOnly = Self.isGetOnlySubscript(subscriptDecl)
                let suffix = Self.subscriptIdentifierSuffix(from: subscriptDecl)

                // Reset subscript call count
                generatedStatements.append("storage.subscript\(suffix)CallCount = 0")

                // Reset subscript call args
                generatedStatements.append("storage.subscript\(suffix)CallArgs = []")

                // Reset subscript handler
                generatedStatements.append("storage.subscript\(suffix)Handler = nil")

                // Reset subscript set handler if not get-only
                if !isGetOnly {
                    generatedStatements.append("storage.subscript\(suffix)SetHandler = nil")
                }
            }

            return generatedStatements
        }

        let resetBody = resetLines
            .map { "    \($0)" }
            .joined(separator: "\n")
        let withLockBody = resetBody.isEmpty ? """
_storage.withLock { storage in
}
""" : """
_storage.withLock { storage in
\(resetBody)
}
"""

        var bodyStatements: [CodeBlockItemSyntax] = []
        if hasParentMock {
            bodyStatements.append(
                CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "super.resetMock()")))
            )
        }
        bodyStatements.append(
            CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: withLockBody)))
        )

        let body = CodeBlockSyntax(
            leftBrace: .leftBraceToken(trailingTrivia: .newline),
            statements: CodeBlockItemListSyntax(bodyStatements),
            rightBrace: .rightBraceToken(leadingTrivia: .newline)
        )

        // For actors, add nonisolated modifier; for inherited mocks, add override
        var additionalModifiers: [DeclModifierSyntax] = []
        if isActor {
            additionalModifiers.append(DeclModifierSyntax(name: .keyword(.nonisolated)))
        }
        if hasParentMock {
            additionalModifiers.append(DeclModifierSyntax(name: .keyword(.override)))
        }

        return FunctionDeclSyntax(
            modifiers: buildModifiers(additional: additionalModifiers),
            name: .identifier("resetMock"),
            signature: FunctionSignatureSyntax(
                parameterClause: FunctionParameterClauseSyntax(
                    leftParen: .leftParenToken(),
                    parameters: FunctionParameterListSyntax([]),
                    rightParen: .rightParenToken()
                )
            ),
            body: body
        )
    }
}
