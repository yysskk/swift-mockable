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
            // Subscript backing storage is always an instance property (`static subscript`
            // is unsupported), so subscript resets are never prefixed. Only func/var members
            // can be `static` and need the `Self.` prefix.
            let prefix = decl.is(SubscriptDeclSyntax.self)
                ? ""
                : (Self.isTypeMember(decl) ? "Self." : "")
            return resetTargets(for: decl, methodGroups: methodGroups, lockBased: false).map { target in
                CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "\(prefix)\(target.name) = \(target.resetValue)")))
            }
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
                guard Self.isTypeMember(decl) == includeTypeMembers else {
                    return []
                }
                return resetTargets(for: decl, methodGroups: methodGroups, lockBased: true).map { target in
                    "storage.\(target.name) = \(target.resetValue)"
                }
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

    /// A single `<member> = <value>` assignment emitted by `resetMock()`.
    ///
    /// `name` is the bare stored-property name; callers prefix it with the storage
    /// accessor appropriate to their model (`Self.` for static members, `storage.`
    /// for the lock-backed model, or nothing for regular instance members).
    private struct ResetTarget {
        let name: String
        let resetValue: String
    }

    /// The reset assignments for a single requirement, shared by the regular and
    /// lock-backed (`Sendable`/actor) reset methods.
    ///
    /// The two models differ only for stored get-set variables: the lock-backed model
    /// always resets the `_name` backing storage, whereas the regular model resets an
    /// optional get-set property directly (it has no backing storage). Pass `lockBased`
    /// to select the model.
    private func resetTargets(
        for decl: DeclSyntax,
        methodGroups: [String: [FunctionDeclSyntax]],
        lockBased: Bool
    ) -> [ResetTarget] {
        if let funcDecl = decl.as(FunctionDeclSyntax.self) {
            let funcName = funcDecl.name.text
            let methodGroup = methodGroups[funcName] ?? []
            let isOverloaded = methodGroup.count > 1
            let suffix = isOverloaded ? Self.functionIdentifierSuffix(from: funcDecl, in: methodGroup) : ""
            let identifier = suffix.isEmpty ? funcName : "\(funcName)\(suffix)"
            return [
                ResetTarget(name: MockNaming.callCount(identifier), resetValue: "0"),
                ResetTarget(name: MockNaming.callArgs(identifier), resetValue: "[]"),
                ResetTarget(name: MockNaming.handler(identifier), resetValue: "nil"),
            ]
        }

        if let varDecl = decl.as(VariableDeclSyntax.self) {
            var targets: [ResetTarget] = []
            for binding in varDecl.bindings {
                guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
                let varName = pattern.identifier.text

                // Effectful read-only properties are handler-based (no `_name` backing).
                if Self.effectfulGetter(of: binding) != nil {
                    targets.append(ResetTarget(name: MockNaming.callCount(varName), resetValue: "0"))
                    targets.append(ResetTarget(name: MockNaming.handler(varName), resetValue: "nil"))
                    continue
                }

                // The lock-backed model always resets `_name` backing storage.
                if lockBased {
                    targets.append(ResetTarget(name: MockNaming.variableBacking(varName), resetValue: "nil"))
                    continue
                }

                guard let typeAnnotation = binding.typeAnnotation else { continue }
                let varType = typeAnnotation.type
                let isOptional = varType.is(OptionalTypeSyntax.self) || varType.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)
                let isGetOnly = Self.isGetOnlyProperty(binding: binding)

                // For get-only properties, always use `_name`. For get-set properties,
                // optional types are reset directly (no backing storage) and non-optional
                // types reset the `_name` backing storage.
                if isGetOnly || !isOptional {
                    targets.append(ResetTarget(name: MockNaming.variableBacking(varName), resetValue: "nil"))
                } else {
                    targets.append(ResetTarget(name: varName, resetValue: "nil"))
                }
            }
            return targets
        }

        if let subscriptDecl = decl.as(SubscriptDeclSyntax.self) {
            let isGetOnly = Self.isGetOnlySubscript(subscriptDecl)
            let suffix = Self.subscriptIdentifierSuffix(from: subscriptDecl)
            let identifier = MockNaming.subscriptIdentifier(suffix: suffix)
            var targets: [ResetTarget] = [
                ResetTarget(name: MockNaming.callCount(identifier), resetValue: "0"),
                ResetTarget(name: MockNaming.callArgs(identifier), resetValue: "[]"),
                ResetTarget(name: MockNaming.handler(identifier), resetValue: "nil"),
            ]
            if !isGetOnly {
                targets.append(ResetTarget(name: MockNaming.setHandler(identifier), resetValue: "nil"))
            }
            return targets
        }

        return []
    }
}
