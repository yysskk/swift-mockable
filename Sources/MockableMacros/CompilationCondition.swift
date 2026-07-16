import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// The compilation condition guarding a generated mock, parsed from the
/// `condition:` argument of `@Mockable`.
///
/// This mirrors the public `MockCompilationCondition` enum declared in the
/// `Mockable` module. The macro implementation cannot import that module (the
/// plugin is compiled independently of it), so the argument is recognized
/// syntactically — the condition must be written literally at the attachment
/// site, because the macro expands at compile time and cannot evaluate runtime
/// values.
enum CompilationCondition: Equatable {
    /// Wrap the mock in `#if DEBUG` (the default when no argument is given).
    case debug
    /// Emit the mock without an `#if` guard.
    case always
    /// Wrap the mock in `#if <flag>` for a custom compilation condition flag.
    case custom(String)

    // MARK: Parsing

    /// Parses the attribute's argument list into a condition.
    ///
    /// Returns `.debug` when no arguments are given, and `nil` (after emitting
    /// diagnostics) when an argument is invalid.
    static func parse(
        from node: AttributeSyntax,
        in context: some MacroExpansionContext
    ) -> CompilationCondition? {
        guard let arguments = node.arguments else {
            return .debug
        }
        guard case .argumentList(let argumentList) = arguments else {
            context.diagnose(
                Diagnostic(
                    node: Syntax(node),
                    message: MockableError.invalidMacroArgument(
                        "the only supported argument is 'condition:'"
                    )
                )
            )
            return nil
        }

        var condition: CompilationCondition?
        var hasError = false

        for argument in argumentList {
            guard let label = argument.label?.text else {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(argument),
                        message: MockableError.invalidMacroArgument(
                            "@Mockable does not accept unlabeled arguments; the only supported argument is 'condition:'"
                        )
                    )
                )
                hasError = true
                continue
            }

            guard label == "condition" else {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(argument),
                        message: MockableError.invalidMacroArgument(
                            "unexpected argument label '\(label)'; the only supported argument is 'condition:'"
                        )
                    )
                )
                hasError = true
                continue
            }

            guard condition == nil else {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(argument),
                        message: MockableError.invalidMacroArgument(
                            "duplicate 'condition' argument"
                        )
                    )
                )
                hasError = true
                continue
            }

            if let parsed = parseConditionValue(argument.expression, in: context) {
                condition = parsed
            } else {
                hasError = true
            }
        }

        if hasError {
            return nil
        }
        return condition ?? .debug
    }

    /// Parses the expression passed to `condition:`.
    ///
    /// Accepts `.debug`, `.always`, and `.custom("FLAG")`, each optionally
    /// qualified (`MockCompilationCondition.debug`). The qualifying base is not
    /// inspected — the compiler has already type-checked the argument as a
    /// `MockCompilationCondition` before the macro expands.
    private static func parseConditionValue(
        _ expression: ExprSyntax,
        in context: some MacroExpansionContext
    ) -> CompilationCondition? {
        if let memberAccess = expression.as(MemberAccessExprSyntax.self) {
            switch memberAccess.declName.baseName.text {
            case "debug":
                return .debug
            case "always":
                return .always
            default:
                break
            }
        }

        if let call = expression.as(FunctionCallExprSyntax.self),
            let memberAccess = call.calledExpression.as(MemberAccessExprSyntax.self),
            memberAccess.declName.baseName.text == "custom" {
            return parseCustomFlag(call, in: context)
        }

        context.diagnose(
            Diagnostic(
                node: Syntax(expression),
                message: MockableError.invalidMacroArgument(
                    "the 'condition' argument must be written literally as '.debug', '.always', or '.custom(\"FLAG\")'"
                )
            )
        )
        return nil
    }

    /// Extracts and validates the flag of `.custom("FLAG")`.
    private static func parseCustomFlag(
        _ call: FunctionCallExprSyntax,
        in context: some MacroExpansionContext
    ) -> CompilationCondition? {
        guard call.arguments.count == 1,
            let argument = call.arguments.first,
            argument.label == nil,
            let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self)
        else {
            context.diagnose(
                Diagnostic(
                    node: Syntax(call),
                    message: MockableError.invalidMacroArgument(
                        "'.custom' requires a single string literal, e.g. '.custom(\"MOCKING\")'"
                    )
                )
            )
            return nil
        }

        var flag = ""
        for segment in stringLiteral.segments {
            guard let stringSegment = segment.as(StringSegmentSyntax.self) else {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(stringLiteral),
                        message: MockableError.invalidMacroArgument(
                            "the custom compilation condition must be a string literal without interpolation"
                        )
                    )
                )
                return nil
            }
            flag += stringSegment.content.text
        }

        guard isValidConditionFlag(flag) else {
            context.diagnose(
                Diagnostic(
                    node: Syntax(stringLiteral),
                    message: MockableError.invalidMacroArgument(
                        "'\(flag)' is not a valid compilation condition flag; use a single identifier such as 'MOCKING'"
                    )
                )
            )
            return nil
        }

        return .custom(flag)
    }

    /// Whether `flag` can be spelled as the condition of an `#if` directive.
    ///
    /// Flags declared via `-D`, `SWIFT_ACTIVE_COMPILATION_CONDITIONS`, or
    /// SwiftPM's `.define` are plain identifiers: a letter or underscore
    /// followed by letters, digits, or underscores.
    private static func isValidConditionFlag(_ flag: String) -> Bool {
        guard let first = flag.first, first == "_" || first.isLetter else {
            return false
        }
        return flag.dropFirst().allSatisfy { character in
            character == "_" || character.isLetter || (character.isNumber && character.isASCII)
        }
    }

    // MARK: Code Generation

    /// Returns `decl` wrapped in `#if <condition>`, or `decl` unchanged for
    /// ``always``.
    func wrapping(_ decl: DeclSyntax) -> DeclSyntax {
        let conditionExpr: ExprSyntax
        switch self {
        case .always:
            return decl
        case .debug:
            conditionExpr = ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("DEBUG")))
        case .custom(let flag):
            conditionExpr = ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier(flag)))
        }

        let ifConfigDecl = IfConfigDeclSyntax(
            clauses: IfConfigClauseListSyntax([
                IfConfigClauseSyntax(
                    poundKeyword: .poundIfToken(),
                    condition: conditionExpr,
                    elements: .decls(MemberBlockItemListSyntax([
                        MemberBlockItemSyntax(decl: decl)
                    ]))
                )
            ])
        )
        return DeclSyntax(ifConfigDecl)
    }
}
