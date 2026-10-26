import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// A diagnostic `@Mockable` emits when it cannot generate a mock.
///
/// Each case carries the facts the message is built from, so the wording lives here
/// and the emission sites only say what they found. Every case is surfaced as a
/// compile-time error at the offending declaration, with a stable `MessageID` in the
/// `MockableMacro` domain so tools can identify it.
enum MockableDiagnostic: DiagnosticMessage {
    /// `@Mockable` was attached to something other than a protocol.
    case notAProtocol
    /// A member kind the macro cannot mock at all (a nested type, an operator
    /// declaration, a `static subscript`). `member` is the member's source text.
    case unsupportedMember(member: String)
    /// `@Mockable` was given an argument it cannot understand.
    case invalidMacroArgument(ArgumentProblem)
    /// An `@autoclosure` parameter whose own `throws`/`async` effects are not covered
    /// by the enclosing requirement, which has to apply `try`/`await` to evaluate it.
    /// `uncoveredEffects` lists the effects the requirement lacks, in the order they
    /// are reported; a subscript requirement cannot carry either, so it is reported
    /// without them.
    case unsupportedAutoclosureEffect(parameter: String, uncoveredEffects: [String], inSubscript: Bool)
    /// A requirement whose name cannot be used to build the mock's tracking
    /// identifiers: an operator, or a name that needs backtick escaping.
    case unsupportedMemberName(name: String, isOperator: Bool)
    /// An `init` requirement declared directly on a protocol whose mock subclasses a
    /// parent protocol's mock, which the macro cannot chain through yet.
    case unsupportedInitializer
    /// An `associatedtype` carrying a constraint but no default, which the mock's
    /// `Any` fallback cannot satisfy.
    case unsupportedAssociatedType(name: String)
    /// An inherited type the generated mock cannot be made to conform to.
    case unsupportedInheritedType(name: String, reason: UnsupportedInheritedType.Reason)
    /// A requirement whose return type mentions a generic parameter inside a function
    /// type, which the mock cannot rebuild from its erased handler result.
    case unsupportedGenericReturn(requirement: String, returnType: String)
    /// A requirement with a closure parameter whose own parameters mention a generic
    /// parameter, which the mock cannot forward to its erased handler.
    case unsupportedGenericParameter(requirement: String, parameter: String, parameterType: String)

    /// What is wrong with an argument passed to `@Mockable`.
    enum ArgumentProblem {
        /// The attribute's arguments are not a labeled argument list.
        case notAnArgumentList
        /// An argument without a label.
        case unlabeled
        /// An argument with a label other than `condition`.
        case unexpectedLabel(String)
        /// `condition:` was passed more than once.
        case duplicateCondition
        /// The `condition:` value is not one of the literal spellings.
        case conditionNotLiteral
        /// `.custom(...)` was given something other than a single string literal.
        case customNotAStringLiteral
        /// The condition's string literal is interpolated.
        case customInterpolated
        /// The `.custom` condition is empty.
        case customEmpty
        /// The `.custom` condition spans more than one line.
        case customMultiline
        /// The `.custom` condition does not parse as an `#if` condition.
        case customUnparsable(String)
        /// The `.custom` condition parses but uses a construct `#if` does not allow.
        case customUnsupported(String)
    }

    /// The text shown at the diagnostic's source location.
    var message: String {
        switch self {
        case .notAProtocol:
            return "@Mockable can only be applied to protocols"

        case .unsupportedMember(let member):
            return "Unsupported protocol member: \(member)"

        case .invalidMacroArgument(let problem):
            return "Invalid @Mockable argument: \(problem.message)"

        case .unsupportedAutoclosureEffect(let parameter, let uncoveredEffects, let inSubscript):
            if inSubscript {
                return "Cannot mock @autoclosure parameter '\(parameter)': effectful autoclosures are not supported in subscript requirements"
            }
            let effects = uncoveredEffects.joined(separator: "' and '")
            return "Cannot mock @autoclosure parameter '\(parameter)': the mock evaluates autoclosure arguments when called, so the requirement must be declared '\(effects)'"

        case .unsupportedMemberName(let name, let isOperator):
            let reason = isOperator
                ? "operator requirements are not supported"
                : "only requirements whose name is a plain identifier can be mocked"
            return "Cannot mock '\(name)': \(reason)"

        case .unsupportedInitializer:
            return "init requirements declared on an inheriting protocol are not yet supported"

        case .unsupportedAssociatedType(let name):
            return """
                Cannot mock associated type '\(name)': the mock fulfills it with 'Any', \
                which does not satisfy its constraints. Give it a default \
                ('associatedtype \(name): ... = SomeType') so the mock has a type to use.
                """

        case .unsupportedInheritedType(let name, let reason):
            switch reason {
            case .requirementsCannotBeWitnessed:
                return """
                    '\(name)' declares requirements @Mockable cannot generate witnesses for, \
                    so the generated mock would not conform to it. Drop the conformance from \
                    the protocol, or satisfy it in an extension of the generated mock.
                    """
            case .parameterized:
                return """
                    '\(name)' is a parent protocol written with generic arguments, which the \
                    generated mock cannot subclass. Inherit from an unparameterized protocol \
                    instead.
                    """
            }

        case .unsupportedGenericReturn(let requirement, let returnType):
            return """
                Cannot mock '\(requirement)': its return type '\(returnType)' mentions a \
                generic parameter inside a function type. The mock erases generic parameters in its \
                handler and casts the result back, and Swift cannot convert between function types \
                at runtime
                """

        case .unsupportedGenericParameter(let requirement, let parameter, let parameterType):
            return """
                Cannot mock '\(requirement)': the parameter '\(parameter)' is a closure whose own \
                parameters mention a generic parameter. The mock forwards it to a handler that \
                erases generic parameters, and a closure taking '\(parameterType)' \
                cannot be passed where one taking erased parameters is expected
                """
        }
    }

    /// Every case is an error: the alternative to reporting is an expansion that does
    /// not compile, so there is nothing a warning would let the build proceed with.
    var severity: DiagnosticSeverity { .error }

    /// The stable identifier tools use to group these diagnostics, one per case.
    var diagnosticID: MessageID {
        MessageID(domain: "MockableMacro", id: identifier)
    }

    private var identifier: String {
        switch self {
        case .notAProtocol:
            return "notAProtocol"
        case .unsupportedMember:
            return "unsupportedMember"
        case .invalidMacroArgument:
            return "invalidMacroArgument"
        case .unsupportedAutoclosureEffect:
            return "unsupportedAutoclosureEffect"
        case .unsupportedMemberName:
            return "unsupportedMemberName"
        case .unsupportedInitializer:
            return "unsupportedInitializer"
        case .unsupportedAssociatedType:
            return "unsupportedAssociatedType"
        case .unsupportedInheritedType:
            return "unsupportedInheritedType"
        case .unsupportedGenericReturn:
            return "unsupportedGenericReturn"
        case .unsupportedGenericParameter:
            return "unsupportedGenericParameter"
        }
    }
}

extension MockableDiagnostic.ArgumentProblem {
    /// The explanation that follows "Invalid @Mockable argument:".
    var message: String {
        switch self {
        case .notAnArgumentList:
            return "the only supported argument is 'condition:'"
        case .unlabeled:
            return "@Mockable does not accept unlabeled arguments; the only supported argument is 'condition:'"
        case .unexpectedLabel(let label):
            return "unexpected argument label '\(label)'; the only supported argument is 'condition:'"
        case .duplicateCondition:
            return "duplicate 'condition' argument"
        case .conditionNotLiteral:
            return "the 'condition' argument must be written literally as '.debug', '.always', a string literal \"CONDITION\", or '.custom(\"CONDITION\")'"
        case .customNotAStringLiteral:
            return "'.custom' requires a single string literal, e.g. '.custom(\"MOCKING\")'"
        case .customInterpolated:
            return "the custom compilation condition must be a string literal without interpolation"
        case .customEmpty:
            return "the custom compilation condition must not be empty"
        case .customMultiline:
            return "the custom compilation condition must be a single line"
        case .customUnparsable(let source):
            return "'\(source)' is not a valid compilation condition expression"
        case .customUnsupported(let source):
            return "'\(source)' is not a supported compilation condition; use identifiers, 'true'/'false', "
                + "'!', '&&', '||', parentheses, and platform checks such as 'os(iOS)', "
                + "'canImport(UIKit)', or 'swift(>=6.0)'"
        }
    }
}

extension MacroExpansionContext {
    /// Reports `diagnostic` at `node`.
    func diagnose(_ diagnostic: MockableDiagnostic, at node: some SyntaxProtocol) {
        diagnose(Diagnostic(node: Syntax(node), message: diagnostic))
    }
}
