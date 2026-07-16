import SwiftDiagnostics
import SwiftParser
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
    /// Wrap the mock in `#if <expression>` for a custom compilation condition.
    case custom(ExprSyntax)

    /// The condition functions the compiler accepts in `#if` directives.
    /// Their arguments are not validated here; the compiler checks them when
    /// the expansion is compiled.
    private static let platformConditionFunctions: Set<String> = [
        "os", "arch", "swift", "compiler", "canImport", "targetEnvironment",
        "hasFeature", "hasAttribute",
    ]

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
    /// Accepts `.debug`, `.always`, and `.custom("<condition>")`, each optionally
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
            return parseCustomCondition(call, in: context)
        }

        context.diagnose(
            Diagnostic(
                node: Syntax(expression),
                message: MockableError.invalidMacroArgument(
                    "the 'condition' argument must be written literally as '.debug', '.always', or '.custom(\"CONDITION\")'"
                )
            )
        )
        return nil
    }

    /// Extracts and validates the condition of `.custom("<condition>")`.
    private static func parseCustomCondition(
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

        var conditionSource = ""
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
            conditionSource += stringSegment.content.text
        }

        guard let conditionExpr = parseConditionExpression(conditionSource, at: stringLiteral, in: context) else {
            return nil
        }

        return .custom(conditionExpr)
    }

    /// Parses `source` as the condition of an `#if` directive and validates it
    /// against the constructs the compiler allows there.
    ///
    /// Returns the parsed expression (trimmed of surrounding trivia), or `nil`
    /// after emitting a diagnostic at `node`.
    private static func parseConditionExpression(
        _ source: String,
        at node: some SyntaxProtocol,
        in context: some MacroExpansionContext
    ) -> ExprSyntax? {
        func diagnose(_ message: String) {
            context.diagnose(
                Diagnostic(
                    node: Syntax(node),
                    message: MockableError.invalidMacroArgument(message)
                )
            )
        }

        guard !source.allSatisfy(\.isWhitespace) else {
            diagnose("the custom compilation condition must not be empty")
            return nil
        }

        // Parse a probe `#if` block so the string is read in exactly the
        // position it will occupy in the expansion. A string that fails to
        // parse here would otherwise surface as a confusing error inside the
        // generated code.
        let probeSource = "#if \(source)\n#endif"
        let probeFile = Parser.parse(source: probeSource)

        guard !probeFile.hasError,
            probeFile.statements.count == 1,
            let ifConfigDecl = probeFile.statements.first?.item.as(IfConfigDeclSyntax.self),
            ifConfigDecl.clauses.count == 1,
            let condition = ifConfigDecl.clauses.first?.condition
        else {
            diagnose("'\(source)' is not a valid compilation condition expression")
            return nil
        }

        guard isSupportedConditionExpression(condition) else {
            diagnose(
                "'\(source)' is not a supported compilation condition; use identifiers, 'true'/'false', "
                    + "'!', '&&', '||', parentheses, and platform checks such as 'os(iOS)', "
                    + "'canImport(UIKit)', or 'swift(>=6.0)'"
            )
            return nil
        }

        return condition.trimmed
    }

    /// Whether `expression` uses only constructs the compiler allows in an
    /// `#if` condition: identifiers, boolean literals, `!`, `&&`, `||`,
    /// parentheses, and the platform condition functions.
    private static func isSupportedConditionExpression(_ expression: ExprSyntax) -> Bool {
        if let declReference = expression.as(DeclReferenceExprSyntax.self) {
            return declReference.argumentNames == nil
        }

        if expression.is(BooleanLiteralExprSyntax.self) {
            return true
        }

        if let prefixOperator = expression.as(PrefixOperatorExprSyntax.self) {
            return prefixOperator.operator.text == "!"
                && isSupportedConditionExpression(prefixOperator.expression)
        }

        if let infixOperator = expression.as(InfixOperatorExprSyntax.self) {
            guard let binaryOperator = infixOperator.operator.as(BinaryOperatorExprSyntax.self),
                binaryOperator.operator.text == "&&" || binaryOperator.operator.text == "||"
            else {
                return false
            }
            return isSupportedConditionExpression(infixOperator.leftOperand)
                && isSupportedConditionExpression(infixOperator.rightOperand)
        }

        // SwiftParser leaves binary-operator chains unfolded as a sequence of
        // alternating operands and operators; `&&`/`||` never mix in an `#if`
        // condition without parentheses anyway, so the flat shape can be
        // validated directly.
        if let sequence = expression.as(SequenceExprSyntax.self) {
            let elements = Array(sequence.elements)
            guard elements.count >= 3, elements.count.isMultiple(of: 2) == false else {
                return false
            }
            for (index, element) in elements.enumerated() {
                if index.isMultiple(of: 2) {
                    guard isSupportedConditionExpression(element) else {
                        return false
                    }
                } else {
                    guard let binaryOperator = element.as(BinaryOperatorExprSyntax.self),
                        binaryOperator.operator.text == "&&" || binaryOperator.operator.text == "||"
                    else {
                        return false
                    }
                }
            }
            return true
        }

        if let tuple = expression.as(TupleExprSyntax.self) {
            guard tuple.elements.count == 1,
                let element = tuple.elements.first,
                element.label == nil
            else {
                return false
            }
            return isSupportedConditionExpression(element.expression)
        }

        if let call = expression.as(FunctionCallExprSyntax.self) {
            guard let callee = call.calledExpression.as(DeclReferenceExprSyntax.self) else {
                return false
            }
            return platformConditionFunctions.contains(callee.baseName.text)
        }

        return false
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
        case .custom(let expression):
            conditionExpr = expression
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
