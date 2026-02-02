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

        // Extract all members including those in #if blocks
        let conditionalMembers = extractConditionalMembers()

        // Group reset statements by their condition
        var unconditionalStatements: [CodeBlockItemSyntax] = []
        var statementsByCondition: [String: [CodeBlockItemSyntax]] = [:]
        var conditionExprs: [String: ExprSyntax] = [:]

        for conditionalMember in conditionalMembers {
            var generatedStatements: [CodeBlockItemSyntax] = []

            if let funcDecl = conditionalMember.decl.as(FunctionDeclSyntax.self) {
                let funcName = funcDecl.name.text
                let isOverloaded = (methodGroups[funcName]?.count ?? 0) > 1
                let suffix = isOverloaded ? Self.functionIdentifierSuffix(from: funcDecl) : ""
                let identifier = suffix.isEmpty ? funcName : "\(funcName)\(suffix)"

                // Reset call count
                generatedStatements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "\(identifier)CallCount = 0"))))

                // Reset call args
                generatedStatements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "\(identifier)CallArgs = []"))))

                // Reset handler
                generatedStatements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "\(identifier)Handler = nil"))))
            } else if let varDecl = conditionalMember.decl.as(VariableDeclSyntax.self) {
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
            } else if let subscriptDecl = conditionalMember.decl.as(SubscriptDeclSyntax.self) {
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

            // Group by condition
            if let condition = conditionalMember.condition {
                let conditionKey = condition.trimmedDescription
                conditionExprs[conditionKey] = condition
                statementsByCondition[conditionKey, default: []].append(contentsOf: generatedStatements)
            } else {
                unconditionalStatements.append(contentsOf: generatedStatements)
            }
        }

        // Add unconditional statements first
        statements.append(contentsOf: unconditionalStatements)

        // Add conditional statements wrapped in their respective #if blocks
        for (conditionKey, condStatements) in statementsByCondition {
            if let condition = conditionExprs[conditionKey] {
                let ifConfigDecl = IfConfigDeclSyntax(
                    clauses: IfConfigClauseListSyntax([
                        IfConfigClauseSyntax(
                            poundKeyword: .poundIfToken(),
                            condition: condition,
                            elements: .statements(CodeBlockItemListSyntax(condStatements))
                        )
                    ])
                )
                statements.append(CodeBlockItemSyntax(item: .decl(DeclSyntax(ifConfigDecl))))
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
        var conditionalResetStatements: [String: [String]] = [:]

        // Group methods by name to detect overloads (including conditional members)
        let methodGroups = groupMethodsByNameIncludingConditional()

        // Extract all members including those in #if blocks
        let conditionalMembers = extractConditionalMembers()

        for conditionalMember in conditionalMembers {
            var generatedStatements: [String] = []

            if let funcDecl = conditionalMember.decl.as(FunctionDeclSyntax.self) {
                let funcName = funcDecl.name.text
                let isOverloaded = (methodGroups[funcName]?.count ?? 0) > 1
                let suffix = isOverloaded ? Self.functionIdentifierSuffix(from: funcDecl) : ""
                let identifier = suffix.isEmpty ? funcName : "\(funcName)\(suffix)"

                // Reset call count
                generatedStatements.append("storage.\(identifier)CallCount = 0")

                // Reset call args
                generatedStatements.append("storage.\(identifier)CallArgs = []")

                // Reset handler
                generatedStatements.append("storage.\(identifier)Handler = nil")
            } else if let varDecl = conditionalMember.decl.as(VariableDeclSyntax.self) {
                for binding in varDecl.bindings {
                    guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
                    let varName = identifier.identifier.text

                    // Reset variable backing storage
                    generatedStatements.append("storage._\(varName) = nil")
                }
            } else if let subscriptDecl = conditionalMember.decl.as(SubscriptDeclSyntax.self) {
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

            // Group by condition
            if let condition = conditionalMember.condition {
                let conditionKey = condition.trimmedDescription
                conditionalResetStatements[conditionKey, default: []].append(contentsOf: generatedStatements)
            } else {
                resetStatements.append(contentsOf: generatedStatements)
            }
        }

        // Build the reset body with unconditional statements first
        var resetBodyLines = resetStatements

        // Add conditional statements wrapped in #if blocks
        for (conditionKey, statements) in conditionalResetStatements {
            resetBodyLines.append("#if \(conditionKey)")
            resetBodyLines.append(contentsOf: statements)
            resetBodyLines.append("#endif")
        }

        let resetBody = resetBodyLines.joined(separator: "\n    ")
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
