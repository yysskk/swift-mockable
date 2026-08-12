import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Reset Method Generation

extension MockGenerator {
    /// Generates `resetMock()`, which clears every requirement's call count, captured
    /// arguments, and handler back to its initial state. The lock-backed variant (for
    /// `Sendable`/actor mocks) resets inside `withLock`; both variants call
    /// `super.resetMock()` first when the mock inherits from a parent mock.
    func generateResetMethod() -> FunctionDeclSyntax {
        if isSendable || isActor {
            return generateSendableResetMethod()
        } else {
            return generateRegularResetMethod()
        }
    }

    /// The plain `resetMock()`: one assignment per tracking slot, addressed through the
    /// mock's own members (`Self.` for type members). Overridden and chained to the
    /// parent's implementation when the mock subclasses one.
    private func generateRegularResetMethod() -> FunctionDeclSyntax {
        var statements: [CodeBlockItemSyntax] = []
        let overloads = makeOverloadContext()

        // The regular reset always assigns through the direct-model names — even a
        // static member's lock-backed slot is reset through its public accessor
        // (`Self.cachedCount = nil`), not the storage-struct field.
        let resetStatements = mapCodeBlockItemsPreservingIfConfig { decl in
            trackingRequirements(for: decl, overloads: overloads).flatMap { requirement in
                let prefix = requirement.isTypeMember ? "Self." : ""
                return requirement.trackingFields(model: .direct).map { field in
                    CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "\(prefix)\(field.name) = \(field.resetValue)")))
                }
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

    /// The lock-backed `resetMock()`: instance slots are cleared in one `withLock` and
    /// static slots in another, so each storage struct is reset atomically. On an actor
    /// mock the method is `nonisolated`, so a test can reset without awaiting.
    private func generateSendableResetMethod() -> FunctionDeclSyntax {
        let overloads = makeOverloadContext()

        func resetLines(forTypeMembers includeTypeMembers: Bool) -> [String] {
            mapLinesPreservingIfConfig { decl in
                guard Self.isTypeMember(decl) == includeTypeMembers else {
                    return []
                }
                return trackingRequirements(for: decl, overloads: overloads).flatMap { requirement in
                    requirement.trackingFields(model: .lockBacked).map { field in
                        "storage.\(field.name) = \(field.resetValue)"
                    }
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

}
