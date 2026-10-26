import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Reset Method Generation

extension MockGenerator {
    /// The assignments that clear one storage struct's fields, addressed through the
    /// `withLock` closure's `storage` binding and keeping the protocol's `#if` structure.
    private func resetLines(for scope: MemberScope, overloads: OverloadContext) -> [String] {
        mapLinesPreservingIfConfig { requirement in
            guard requirement.scope == scope else {
                return []
            }
            return trackingRequirements(for: requirement, overloads: overloads).flatMap { tracking in
                tracking.trackingFields(model: .lockBacked).map { field in
                    "storage.\(field.name) = \(field.initialValue.trimmedDescription)"
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

    /// Generates the instance `resetMock()`, which clears every instance requirement's
    /// call count, captured arguments, handler, and stored property back to its initial
    /// state. Type state is shared by every instance and is cleared by the type-level
    /// ``generateTypeResetMethod()`` instead. The lock-backed variant (for
    /// `Sendable`/actor mocks) resets inside `withLock`; both variants call
    /// `super.resetMock()` first when the mock inherits from a parent mock.
    func generateResetMethod() -> FunctionDeclSyntax {
        // The two variants address a requirement's slots by different names — an
        // optional property is its own storage on the direct path but has a `_name`
        // field in the storage struct — so the choice has to follow the same predicate
        // the members were generated from.
        if usesInstanceStorageLock {
            return generateLockBackedResetMethod()
        } else {
            return generateRegularResetMethod()
        }
    }

    /// The plain `resetMock()`: one assignment per instance tracking slot, addressed
    /// through the mock's own members. Overridden and chained to the parent's
    /// implementation when the mock subclasses one.
    private func generateRegularResetMethod() -> FunctionDeclSyntax {
        var statements: [CodeBlockItemSyntax] = []

        // Instance slots are plain stored properties here, so they are assigned through
        // the direct-model names.
        let resetStatements = mapCodeBlockItemsPreservingIfConfig { requirement in
            guard requirement.scope == .instance else {
                return []
            }
            return trackingRequirements(for: requirement, overloads: overloads).flatMap { tracking in
                tracking.trackingFields(model: .direct).map { field in
                    CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "\(field.name) = \(field.initialValue.trimmedDescription)")))
                }
            }
        }

        if shape.subclassesParentMock {
            statements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "super.\(MockNaming.resetMethodName)()"))))
        }

        statements.append(contentsOf: resetStatements)

        let additionalModifiers: [DeclModifierSyntax] = shape.subclassesParentMock
            ? [DeclModifierSyntax(name: .keyword(.override))]
            : []

        return makeResetMethod(additionalModifiers: additionalModifiers, statements: statements)
    }

    /// The lock-backed `resetMock()`: the instance slots are cleared in one `withLock`,
    /// so the storage struct is reset atomically. On an actor mock the method is
    /// `nonisolated`, so a test can reset without awaiting.
    private func generateLockBackedResetMethod() -> FunctionDeclSyntax {
        var statements: [CodeBlockItemSyntax] = []
        if shape.subclassesParentMock {
            statements.append(
                CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "super.\(MockNaming.resetMethodName)()")))
            )
        }
        statements.append(
            CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: buildWithLockBody(
                storageName: MockNaming.instanceStorageName,
                resetLines: resetLines(for: .instance, overloads: overloads)
            ))))
        )

        // This body only touches the lock, so it is nonisolated wherever the mock has
        // nonisolated members to reset: on an actor mock, and on an isolated mock with
        // a requirement that leaves its isolation, whose state a test sets up without
        // hopping to the actor and should be able to clear the same way. An override is left
        // unmarked: it takes the isolation of the parent's `resetMock()`, which the
        // macro cannot see and the `super` call has to be able to reach.
        var additionalModifiers: [DeclModifierSyntax] = []
        if shape.subclassesParentMock {
            additionalModifiers.append(DeclModifierSyntax(name: .keyword(.override)))
        } else if shape.isActor || hasRequirementsLeavingIsolation {
            additionalModifiers.append(DeclModifierSyntax(name: .keyword(.nonisolated)))
        }

        return makeResetMethod(additionalModifiers: additionalModifiers, statements: statements)
    }

    /// Generates the type-level `resetMock()`, which clears every `static` requirement's
    /// tracking state. Type state is shared by every instance, so clearing it from an
    /// instance would be a side effect on every other instance and on every test that
    /// shares the mock type; it is cleared through the type instead:
    /// `ServiceMock.resetMock()`.
    ///
    /// Every mock declares it, with an empty body when the protocol has no `static`
    /// requirement, so that a child mock can override its parent's and chain to it
    /// without the macro knowing whether the parent protocol declares any: a class
    /// mock's is a `class` method, and a child mock's overrides it and calls
    /// `super.resetMock()` first. An actor mock, which cannot be subclassed, declares a
    /// `static` method. The static slots are lock-backed even in a mock whose instance
    /// state is not, and are cleared in one acquisition rather than one per slot: a
    /// caller recording a call concurrently would otherwise see a half-reset mock.
    func generateTypeResetMethod() -> FunctionDeclSyntax {
        var statements: [CodeBlockItemSyntax] = []
        if shape.subclassesParentMock {
            statements.append(
                CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "super.\(MockNaming.resetMethodName)()")))
            )
        }
        let staticResetLines = resetLines(for: .type, overloads: overloads)
        if !staticResetLines.isEmpty {
            statements.append(
                CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: buildWithLockBody(
                    storageName: "Self.\(MockNaming.staticStorageName)",
                    resetLines: staticResetLines
                ))))
            )
        }

        // The body only touches the static lock, so on a global-actor-isolated mock
        // with members outside its isolation it is nonisolated, like the instance
        // method, and a test clears both the same way. An actor's static members are
        // nonisolated already, and an override takes the parent's isolation.
        var additionalModifiers: [DeclModifierSyntax] = []
        if shape.subclassesParentMock {
            additionalModifiers.append(DeclModifierSyntax(name: .keyword(.override)))
        } else if !shape.isActor, hasRequirementsLeavingIsolation {
            additionalModifiers.append(DeclModifierSyntax(name: .keyword(.nonisolated)))
        }
        additionalModifiers.append(DeclModifierSyntax(name: .keyword(shape.isActor ? .static : .class)))

        return makeResetMethod(additionalModifiers: additionalModifiers, statements: statements)
    }

    /// Builds a `resetMock()` declaration with the given modifiers and body. The
    /// method is overridable from other modules wherever the mock type can be
    /// subclassed there.
    private func makeResetMethod(
        additionalModifiers: [DeclModifierSyntax],
        statements: [CodeBlockItemSyntax]
    ) -> FunctionDeclSyntax {
        FunctionDeclSyntax(
            modifiers: modifiers(
                for: shape.canBeSubclassedOutsideModule ? .overridableMember : .member,
                additional: additionalModifiers
            ),
            name: .identifier(MockNaming.resetMethodName),
            signature: FunctionSignatureSyntax(
                parameterClause: FunctionParameterClauseSyntax(
                    leftParen: .leftParenToken(),
                    parameters: FunctionParameterListSyntax([]),
                    rightParen: .rightParenToken()
                )
            ),
            body: Self.makeBody(statements)
        )
    }

    /// A method body laid out one statement per line, or an empty pair of braces.
    private static func makeBody(_ statements: [CodeBlockItemSyntax]) -> CodeBlockSyntax {
        guard !statements.isEmpty else {
            return CodeBlockSyntax(statements: CodeBlockItemListSyntax([]))
        }
        return CodeBlockSyntax(
            leftBrace: .leftBraceToken(trailingTrivia: .newline),
            statements: CodeBlockItemListSyntax(statements),
            rightBrace: .rightBraceToken(leadingTrivia: .newline)
        )
    }
}
