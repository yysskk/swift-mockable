import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Conditional Compilation Traversal

extension MockGenerator {
    func collectDeclsIncludingConditional(from members: MemberBlockItemListSyntax? = nil) -> [DeclSyntax] {
        collectDecls(from: members ?? self.members)
    }

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

    private func collectDecls(from ifConfigDecl: IfConfigDeclSyntax) -> [DeclSyntax] {
        var result: [DeclSyntax] = []

        for clause in ifConfigDecl.clauses {
            guard clause.condition != nil,
                  let elements = clause.elements,
                  case .decls(let decls) = elements else {
                continue
            }

            result.append(contentsOf: collectDecls(from: decls))
        }

        return result
    }

    private func mapIfConfigDeclToMembers(
        _ ifConfigDecl: IfConfigDeclSyntax,
        transform: (DeclSyntax) -> [MemberBlockItemSyntax]
    ) -> IfConfigDeclSyntax? {
        var hasGeneratedContent = false

        let clauses = IfConfigClauseListSyntax(
            ifConfigDecl.clauses.map { clause in
                let mappedElements: IfConfigClauseSyntax.Elements?
                if let elements = clause.elements,
                   case .decls(let decls) = elements {
                    let mappedMembers = mapMemberBlockItemsPreservingIfConfig(from: decls, transform: transform)
                    if !mappedMembers.isEmpty {
                        hasGeneratedContent = true
                    }
                    mappedElements = .decls(MemberBlockItemListSyntax(mappedMembers))
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

    private func mapIfConfigDeclToStatements(
        _ ifConfigDecl: IfConfigDeclSyntax,
        transform: (DeclSyntax) -> [CodeBlockItemSyntax]
    ) -> IfConfigDeclSyntax? {
        var hasGeneratedContent = false

        let clauses = IfConfigClauseListSyntax(
            ifConfigDecl.clauses.map { clause in
                let mappedElements: IfConfigClauseSyntax.Elements?
                if let elements = clause.elements,
                   case .decls(let decls) = elements {
                    let mappedStatements = mapCodeBlockItemsPreservingIfConfig(from: decls, transform: transform)
                    if !mappedStatements.isEmpty {
                        hasGeneratedContent = true
                    }
                    mappedElements = .statements(CodeBlockItemListSyntax(mappedStatements))
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
