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
                let prefix = Self.isTypeMember(funcDecl.modifiers) ? "Self." : ""

                // Reset call count
                generatedStatements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "\(prefix)\(MockNaming.callCount(identifier)) = 0"))))

                // Reset call args
                generatedStatements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "\(prefix)\(MockNaming.callArgs(identifier)) = []"))))

                // Reset handler
                generatedStatements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "\(prefix)\(MockNaming.handler(identifier)) = nil"))))
            } else if let varDecl = decl.as(VariableDeclSyntax.self) {
                let prefix = Self.isTypeMember(varDecl.modifiers) ? "Self." : ""

                for binding in varDecl.bindings {
                    guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                          let typeAnnotation = binding.typeAnnotation else { continue }

                    let varName = identifier.identifier.text
                    let varType = typeAnnotation.type

                    // Effectful read-only properties are handler-based (no `_name` backing).
                    if Self.effectfulGetter(of: binding) != nil {
                        generatedStatements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "\(prefix)\(MockNaming.callCount(varName)) = 0"))))
                        generatedStatements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "\(prefix)\(MockNaming.handler(varName)) = nil"))))
                        continue
                    }

                    let isOptional = varType.is(OptionalTypeSyntax.self) || varType.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)
                    let isGetOnly = Self.isGetOnlyProperty(binding: binding)

                    // For get-only properties, always use _varName
                    // For get-set properties:
                    //   - Optional types use varName directly (no backing storage)
                    //   - Non-optional types use _varName backing storage
                    if isGetOnly || !isOptional {
                        generatedStatements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "\(prefix)\(MockNaming.variableBacking(varName)) = nil"))))
                    } else {
                        generatedStatements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "\(prefix)\(varName) = nil"))))
                    }
                }
            } else if let subscriptDecl = decl.as(SubscriptDeclSyntax.self) {
                let isGetOnly = Self.isGetOnlySubscript(subscriptDecl)
                let suffix = Self.subscriptIdentifierSuffix(from: subscriptDecl)

                // Reset subscript call count
                generatedStatements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "\(MockNaming.callCount(MockNaming.subscriptIdentifier(suffix: suffix))) = 0"))))

                // Reset subscript call args
                generatedStatements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "\(MockNaming.callArgs(MockNaming.subscriptIdentifier(suffix: suffix))) = []"))))

                // Reset subscript handler
                generatedStatements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "\(MockNaming.handler(MockNaming.subscriptIdentifier(suffix: suffix))) = nil"))))

                // Reset subscript set handler if not get-only
                if !isGetOnly {
                    generatedStatements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "\(MockNaming.setHandler(MockNaming.subscriptIdentifier(suffix: suffix))) = nil"))))
                }
            }

            return generatedStatements
        }

        // Add super.resetMock() call if inheriting from parent mock
        if hasParentMock {
            statements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "super.\(MockNaming.resetMethodName)()"))))
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
            modifiers: buildModifiers(
                additional: additionalModifiers,
                isOverridable: canBeSubclassedOutsideModule
            ),
            name: .identifier(MockNaming.resetMethodName),
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

        func resetLines(forTypeMembers includeTypeMembers: Bool) -> [String] {
            mapLinesPreservingIfConfig { decl in
                var generatedStatements: [String] = []
                let isTypeMember = Self.isTypeMember(decl)

                guard isTypeMember == includeTypeMembers else {
                    return generatedStatements
                }

                if let funcDecl = decl.as(FunctionDeclSyntax.self) {
                    let funcName = funcDecl.name.text
                    let methodGroup = methodGroups[funcName] ?? []
                    let isOverloaded = methodGroup.count > 1
                    let suffix = isOverloaded ? Self.functionIdentifierSuffix(from: funcDecl, in: methodGroup) : ""
                    let identifier = suffix.isEmpty ? funcName : "\(funcName)\(suffix)"

                    // Reset call count
                    generatedStatements.append("storage.\(MockNaming.callCount(identifier)) = 0")

                    // Reset call args
                    generatedStatements.append("storage.\(MockNaming.callArgs(identifier)) = []")

                    // Reset handler
                    generatedStatements.append("storage.\(MockNaming.handler(identifier)) = nil")
                } else if let varDecl = decl.as(VariableDeclSyntax.self) {
                    for binding in varDecl.bindings {
                        guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
                        let varName = identifier.identifier.text

                        // Effectful read-only properties are handler-based (no `_name` backing).
                        if Self.effectfulGetter(of: binding) != nil {
                            generatedStatements.append("storage.\(MockNaming.callCount(varName)) = 0")
                            generatedStatements.append("storage.\(MockNaming.handler(varName)) = nil")
                            continue
                        }

                        // Reset variable backing storage
                        generatedStatements.append("storage.\(MockNaming.variableBacking(varName)) = nil")
                    }
                } else if let subscriptDecl = decl.as(SubscriptDeclSyntax.self) {
                    let isGetOnly = Self.isGetOnlySubscript(subscriptDecl)
                    let suffix = Self.subscriptIdentifierSuffix(from: subscriptDecl)

                    // Reset subscript call count
                    generatedStatements.append("storage.\(MockNaming.callCount(MockNaming.subscriptIdentifier(suffix: suffix))) = 0")

                    // Reset subscript call args
                    generatedStatements.append("storage.\(MockNaming.callArgs(MockNaming.subscriptIdentifier(suffix: suffix))) = []")

                    // Reset subscript handler
                    generatedStatements.append("storage.\(MockNaming.handler(MockNaming.subscriptIdentifier(suffix: suffix))) = nil")

                    // Reset subscript set handler if not get-only
                    if !isGetOnly {
                        generatedStatements.append("storage.\(MockNaming.setHandler(MockNaming.subscriptIdentifier(suffix: suffix))) = nil")
                    }
                }

                return generatedStatements
            }
        }

        func buildWithLockBody(storageName: String, resetLines: [String]) -> String {
            let resetBody = resetLines
                .map { "    \($0)" }
                .joined(separator: "\n")

            if resetBody.isEmpty {
                return """
\(storageName).withLock { storage in
}
"""
            }

            return """
\(storageName).withLock { storage in
\(resetBody)
}
"""
        }

        let instanceResetLines = resetLines(forTypeMembers: false)
        let staticResetLines = resetLines(forTypeMembers: true)

        var bodyStatements: [CodeBlockItemSyntax] = []
        if hasParentMock {
            bodyStatements.append(
                CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "super.\(MockNaming.resetMethodName)()")))
            )
        }
        bodyStatements.append(
            CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: buildWithLockBody(storageName: MockNaming.instanceStorageName, resetLines: instanceResetLines))))
        )
        if !staticResetLines.isEmpty {
            bodyStatements.append(
                CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: buildWithLockBody(storageName: "Self.\(MockNaming.staticStorageName)", resetLines: staticResetLines))))
            )
        }

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
            modifiers: buildModifiers(
                additional: additionalModifiers,
                isOverridable: canBeSubclassedOutsideModule
            ),
            name: .identifier(MockNaming.resetMethodName),
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
