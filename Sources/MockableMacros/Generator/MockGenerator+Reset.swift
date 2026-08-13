import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Reset Method Generation

extension MockGenerator {
    /// The assignments that clear one storage struct's fields, addressed through the
    /// `withLock` closure's `storage` binding and keeping the protocol's `#if` structure.
    private func resetLines(forTypeMembers includeTypeMembers: Bool, overloads: OverloadContext) -> [String] {
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

    /// Wraps reset assignments in a single `withLock`, so the slots a caller can observe
    /// together are cleared together.
    private func buildWithLockBody(storageName: String, resetLines: [String]) -> String {
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

    /// Generates `resetMock()`, which clears every requirement's call count, captured
    /// arguments, and handler back to its initial state. The lock-backed variant (for
    /// `Sendable`/actor mocks) resets inside `withLock`; both variants call
    /// `super.resetMock()` first when the mock inherits from a parent mock.
    func generateResetMethod() -> FunctionDeclSyntax {
        // The two variants address a requirement's slots by different names — an
        // optional get-set property is its own storage on the direct path but has a
        // `_name` field in the storage struct — so the choice has to follow the same
        // predicate the members were generated from.
        if usesInstanceStorageLock {
            return generateLockBackedResetMethod()
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

        // Instance slots are plain stored properties here, so they are assigned through
        // the direct-model names.
        let resetStatements = mapCodeBlockItemsPreservingIfConfig { decl in
            guard !Self.isTypeMember(decl) else {
                return []
            }
            return trackingRequirements(for: decl, overloads: overloads).flatMap { requirement in
                requirement.trackingFields(model: .direct).map { field in
                    CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "\(field.name) = \(field.resetValue)")))
                }
            }
        }

        // Add super.resetMock() call if inheriting from parent mock
        if hasParentMock {
            statements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "super.\(MockNaming.resetMethodName)()"))))
        }

        statements.append(contentsOf: resetStatements)

        // Static slots are lock-backed even in a mock whose instance state is not, so
        // they are cleared in one acquisition rather than one per slot: a caller
        // recording a call concurrently would otherwise see a half-reset mock.
        let staticResetLines = resetLines(forTypeMembers: true, overloads: overloads)
        if !staticResetLines.isEmpty {
            statements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: buildWithLockBody(
                storageName: "Self.\(MockNaming.staticStorageName)",
                resetLines: staticResetLines
            )))))
        }

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
    private func generateLockBackedResetMethod() -> FunctionDeclSyntax {
        let overloads = makeOverloadContext()
        let instanceResetLines = resetLines(forTypeMembers: false, overloads: overloads)
        let staticResetLines = resetLines(forTypeMembers: true, overloads: overloads)

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

        // This body only touches the lock, so it is nonisolated wherever the mock has
        // nonisolated members to reset: on an actor mock, and on an isolated mock with
        // a `nonisolated` requirement, whose state a test sets up without hopping to
        // the actor and should be able to clear the same way.
        var additionalModifiers: [DeclModifierSyntax] = []
        if isActor || hasNonisolatedRequirements {
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
