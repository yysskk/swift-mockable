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

        // Group methods by name to detect overloads
        let methodGroups = groupMethodsByName()

        for member in members {
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                let funcName = funcDecl.name.text
                let isOverloaded = (methodGroups[funcName]?.count ?? 0) > 1
                let suffix = isOverloaded ? Self.functionIdentifierSuffix(from: funcDecl) : ""
                let identifier = suffix.isEmpty ? funcName : "\(funcName)\(suffix)"

                // Reset call count
                statements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "\(identifier)CallCount = 0"))))

                // Reset call args
                statements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "\(identifier)CallArgs = []"))))

                // Reset handler
                statements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "\(identifier)Handler = nil"))))
            } else if let varDecl = member.decl.as(VariableDeclSyntax.self) {
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
                        statements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "_\(varName) = nil"))))
                    } else {
                        statements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "\(varName) = nil"))))
                    }
                }
            } else if let subscriptDecl = member.decl.as(SubscriptDeclSyntax.self) {
                let isGetOnly = Self.isGetOnlySubscript(subscriptDecl)
                let suffix = Self.subscriptIdentifierSuffix(from: subscriptDecl)

                // Reset subscript call count
                statements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "subscript\(suffix)CallCount = 0"))))

                // Reset subscript call args
                statements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "subscript\(suffix)CallArgs = []"))))

                // Reset subscript handler
                statements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "subscript\(suffix)Handler = nil"))))

                // Reset subscript set handler if not get-only
                if !isGetOnly {
                    statements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "subscript\(suffix)SetHandler = nil"))))
                }
            }
        }

        let body = CodeBlockSyntax(
            leftBrace: .leftBraceToken(trailingTrivia: .newline),
            statements: CodeBlockItemListSyntax(statements),
            rightBrace: .rightBraceToken(leadingTrivia: .newline)
        )

        return FunctionDeclSyntax(
            modifiers: DeclModifierListSyntax([
                DeclModifierSyntax(name: .keyword(.public))
            ]),
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
        var resetStatements: [String] = []

        // Group methods by name to detect overloads
        let methodGroups = groupMethodsByName()

        for member in members {
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                let funcName = funcDecl.name.text
                let isOverloaded = (methodGroups[funcName]?.count ?? 0) > 1
                let suffix = isOverloaded ? Self.functionIdentifierSuffix(from: funcDecl) : ""
                let identifier = suffix.isEmpty ? funcName : "\(funcName)\(suffix)"

                // Reset call count
                resetStatements.append("storage.\(identifier)CallCount = 0")

                // Reset call args
                resetStatements.append("storage.\(identifier)CallArgs = []")

                // Reset handler
                resetStatements.append("storage.\(identifier)Handler = nil")
            } else if let varDecl = member.decl.as(VariableDeclSyntax.self) {
                for binding in varDecl.bindings {
                    guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
                    let varName = identifier.identifier.text

                    // Reset variable backing storage
                    resetStatements.append("storage._\(varName) = nil")
                }
            } else if let subscriptDecl = member.decl.as(SubscriptDeclSyntax.self) {
                let isGetOnly = Self.isGetOnlySubscript(subscriptDecl)
                let suffix = Self.subscriptIdentifierSuffix(from: subscriptDecl)

                // Reset subscript call count
                resetStatements.append("storage.subscript\(suffix)CallCount = 0")

                // Reset subscript call args
                resetStatements.append("storage.subscript\(suffix)CallArgs = []")

                // Reset subscript handler
                resetStatements.append("storage.subscript\(suffix)Handler = nil")

                // Reset subscript set handler if not get-only
                if !isGetOnly {
                    resetStatements.append("storage.subscript\(suffix)SetHandler = nil")
                }
            }
        }

        let resetBody = resetStatements.joined(separator: "\n    ")
        let withLockBody = """
_storage.withLock { storage in
    \(resetBody)
}
"""

        let body = CodeBlockSyntax(
            leftBrace: .leftBraceToken(trailingTrivia: .newline),
            statements: CodeBlockItemListSyntax([
                CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: withLockBody)))
            ]),
            rightBrace: .rightBraceToken(leadingTrivia: .newline)
        )

        var modifiers: [DeclModifierSyntax] = [
            DeclModifierSyntax(name: .keyword(.public))
        ]

        // For actors, add nonisolated modifier
        if isActor {
            modifiers.append(DeclModifierSyntax(name: .keyword(.nonisolated)))
        }

        return FunctionDeclSyntax(
            modifiers: DeclModifierListSyntax(modifiers),
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
