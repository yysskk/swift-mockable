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

        for member in members {
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                let funcName = funcDecl.name.text

                // Reset call count
                statements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "\(funcName)CallCount = 0"))))

                // Reset call args
                statements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "\(funcName)CallArgs = []"))))

                // Reset handler
                statements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "\(funcName)Handler = nil"))))
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

        for member in members {
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                let funcName = funcDecl.name.text

                // Reset call count
                resetStatements.append("storage.\(funcName)CallCount = 0")

                // Reset call args
                resetStatements.append("storage.\(funcName)CallArgs = []")

                // Reset handler
                resetStatements.append("storage.\(funcName)Handler = nil")
            } else if let varDecl = member.decl.as(VariableDeclSyntax.self) {
                for binding in varDecl.bindings {
                    guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
                    let varName = identifier.identifier.text

                    // Reset variable backing storage
                    resetStatements.append("storage._\(varName) = nil")
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
