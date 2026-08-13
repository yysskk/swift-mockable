import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Conditional Compilation Traversal

extension MockGenerator {
    /// Every requirement the protocol declares, flattened out of any
    /// conditional-compilation blocks, for analyses that need the whole set at once
    /// (overload grouping, type-member detection, initializer collection).
    ///
    /// Flattening loses the `#if` structure, so this is only for analysis: generation
    /// goes through the `map*PreservingIfConfig` drivers below, which keep it. Every
    /// clause is collected, including `#else`, so these analyses see exactly the
    /// requirements generation emits members for.
    func collectDeclsIncludingConditional(from members: MemberBlockItemListSyntax? = nil) -> [DeclSyntax] {
        collectDecls(from: members ?? self.members)
    }

    /// Maps each requirement to mock members, re-emitting any `#if` block around the
    /// members generated from its clauses, so a conditionally declared requirement's
    /// mock is guarded by the same condition.
    func mapMemberBlockItemsPreservingIfConfig(
        from members: MemberBlockItemListSyntax? = nil,
        transform: (DeclSyntax) -> [MemberBlockItemSyntax]
    ) -> [MemberBlockItemSyntax] {
        var result: [MemberBlockItemSyntax] = []

        for member in members ?? self.members {
            if let ifConfigDecl = member.decl.as(IfConfigDeclSyntax.self) {
                guard let mappedIfConfig = mapIfConfigDeclToMembers(ifConfigDecl, transform: transform) else {
                    continue
                }
                result.append(MemberBlockItemSyntax(decl: DeclSyntax(mappedIfConfig)))
            } else {
                result.append(contentsOf: transform(member.decl))
            }
        }

        return result
    }

    /// The statement-producing counterpart of `mapMemberBlockItemsPreservingIfConfig`,
    /// used for `resetMock()`'s body: the `#if` block is re-emitted around the
    /// statements generated from its clauses.
    func mapCodeBlockItemsPreservingIfConfig(
        from members: MemberBlockItemListSyntax? = nil,
        transform: (DeclSyntax) -> [CodeBlockItemSyntax]
    ) -> [CodeBlockItemSyntax] {
        var result: [CodeBlockItemSyntax] = []

        for member in members ?? self.members {
            if let ifConfigDecl = member.decl.as(IfConfigDeclSyntax.self) {
                guard let mappedIfConfig = mapIfConfigDeclToStatements(ifConfigDecl, transform: transform) else {
                    continue
                }
                result.append(CodeBlockItemSyntax(item: .decl(DeclSyntax(mappedIfConfig))))
            } else {
                result.append(contentsOf: transform(member.decl))
            }
        }

        return result
    }

    /// The raw-line counterpart, used for the lock-backed `resetMock()` body: its
    /// assignments live inside a `withLock` closure built as a string, so the `#if`
    /// clauses are emitted as literal `#if`/`#elseif`/`#else`/`#endif` lines.
    func mapLinesPreservingIfConfig(
        from members: MemberBlockItemListSyntax? = nil,
        transform: (DeclSyntax) -> [String]
    ) -> [String] {
        var result: [String] = []

        for member in members ?? self.members {
            if let ifConfigDecl = member.decl.as(IfConfigDeclSyntax.self) {
                result.append(contentsOf: mapIfConfigDeclToLines(ifConfigDecl, transform: transform))
            } else {
                result.append(contentsOf: transform(member.decl))
            }
        }

        return result
    }

    /// Flattens a member list, recursing into conditional-compilation blocks.
    private func collectDecls(from members: MemberBlockItemListSyntax) -> [DeclSyntax] {
        var result: [DeclSyntax] = []

        for member in members {
            if let ifConfigDecl = member.decl.as(IfConfigDeclSyntax.self) {
                result.append(contentsOf: collectDecls(from: ifConfigDecl))
            } else {
                result.append(member.decl)
            }
        }

        return result
    }

    /// Flattens the clauses of a conditional-compilation block.
    ///
    /// Every clause is collected, `#else` included, so these analyses cover the same
    /// requirements the mapping drivers generate members for. Clauses are mutually
    /// exclusive at compile time, but the mock declares the members of all of them
    /// (each under its own condition), so requirements in sibling clauses share one
    /// namespace and are grouped and disambiguated together. This matches
    /// `MockableMacro.declClauses(of:)`, which visits every clause for diagnostics.
    private func collectDecls(from ifConfigDecl: IfConfigDeclSyntax) -> [DeclSyntax] {
        var result: [DeclSyntax] = []

        for clause in ifConfigDecl.clauses {
            guard let elements = clause.elements,
                  case .decls(let decls) = elements else {
                continue
            }

            result.append(contentsOf: collectDecls(from: decls))
        }

        return result
    }

    /// Maps every `.decls` clause of a conditional-compilation block through
    /// `mapDecls`, rebuilding the block with `makeElements` and normalized clause
    /// keywords. Returns `nil` when no clause produced content, so the caller drops
    /// the empty `#if` entirely.
    private func mapIfConfigDeclClauses<Item>(
        _ ifConfigDecl: IfConfigDeclSyntax,
        mapDecls: (MemberBlockItemListSyntax) -> [Item],
        makeElements: ([Item]) -> IfConfigClauseSyntax.Elements
    ) -> IfConfigDeclSyntax? {
        var hasGeneratedContent = false

        let clauses = IfConfigClauseListSyntax(
            ifConfigDecl.clauses.map { clause in
                let mappedElements: IfConfigClauseSyntax.Elements?
                if let elements = clause.elements,
                   case .decls(let decls) = elements {
                    let mappedItems = mapDecls(decls)
                    if !mappedItems.isEmpty {
                        hasGeneratedContent = true
                    }
                    mappedElements = makeElements(mappedItems)
                } else {
                    mappedElements = clause.elements
                }

                return IfConfigClauseSyntax(
                    poundKeyword: normalizedPoundKeyword(for: clause),
                    condition: clause.condition,
                    elements: mappedElements
                )
            }
        )

        guard hasGeneratedContent else {
            return nil
        }

        return IfConfigDeclSyntax(clauses: clauses)
    }

    /// The member-producing case of `mapIfConfigDeclClauses`.
    private func mapIfConfigDeclToMembers(
        _ ifConfigDecl: IfConfigDeclSyntax,
        transform: (DeclSyntax) -> [MemberBlockItemSyntax]
    ) -> IfConfigDeclSyntax? {
        mapIfConfigDeclClauses(
            ifConfigDecl,
            mapDecls: { mapMemberBlockItemsPreservingIfConfig(from: $0, transform: transform) },
            makeElements: { .decls(MemberBlockItemListSyntax($0)) }
        )
    }

    /// The statement-producing case of `mapIfConfigDeclClauses`.
    private func mapIfConfigDeclToStatements(
        _ ifConfigDecl: IfConfigDeclSyntax,
        transform: (DeclSyntax) -> [CodeBlockItemSyntax]
    ) -> IfConfigDeclSyntax? {
        mapIfConfigDeclClauses(
            ifConfigDecl,
            mapDecls: { mapCodeBlockItemsPreservingIfConfig(from: $0, transform: transform) },
            makeElements: { .statements(CodeBlockItemListSyntax($0)) }
        )
    }

    /// The raw-line variant: emits each clause's keyword and condition as literal
    /// lines around its mapped content, closing with `#endif`. Kept separate from
    /// `mapIfConfigDeclClauses` because it produces flat strings rather than a
    /// rebuilt syntax node. Returns an empty array when no clause produced lines.
    private func mapIfConfigDeclToLines(
        _ ifConfigDecl: IfConfigDeclSyntax,
        transform: (DeclSyntax) -> [String]
    ) -> [String] {
        var lines: [String] = []
        var hasGeneratedContent = false

        for clause in ifConfigDecl.clauses {
            let mappedLines: [String]
            if let elements = clause.elements,
               case .decls(let decls) = elements {
                mappedLines = mapLinesPreservingIfConfig(from: decls, transform: transform)
            } else {
                mappedLines = []
            }

            if !mappedLines.isEmpty {
                hasGeneratedContent = true
            }

            if let condition = clause.condition {
                lines.append("\(clause.poundKeyword.text) \(condition.trimmedDescription)")
            } else {
                lines.append(clause.poundKeyword.text)
            }
            lines.append(contentsOf: mappedLines)
        }

        guard hasGeneratedContent else {
            return []
        }

        lines.append("#endif")
        return lines
    }

    /// Rebuilds a clause keyword without the source's surrounding trivia, so the
    /// re-emitted `#if` block is laid out by the formatter rather than inheriting
    /// the protocol's indentation.
    private func normalizedPoundKeyword(for clause: IfConfigClauseSyntax) -> TokenSyntax {
        switch clause.poundKeyword.text {
        case "#if":
            return .poundIfToken()
        case "#elseif":
            return .poundElseifToken()
        case "#else":
            return .poundElseToken()
        default:
            return clause.poundKeyword.with(\.leadingTrivia, []).with(\.trailingTrivia, [])
        }
    }
}
