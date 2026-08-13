import SwiftDiagnostics

/// A diagnostic emitted by `@Mockable` when it cannot generate a mock.
///
/// Each case is surfaced as a compile-time error at the offending declaration,
/// carrying a `MessageID` in the `MockableMacro` domain so tools can identify it.
enum MockableError: Error, CustomStringConvertible, DiagnosticMessage {
    /// `@Mockable` was attached to something other than a protocol.
    case notAProtocol
    /// A protocol member that the macro cannot mock (e.g. an initializer or a
    /// `static subscript`). The associated value is the member's source text.
    case unsupportedMember(String)
    /// `@Mockable` was given an argument it cannot understand — an unknown label,
    /// or a `condition:` value that is not written literally as `.debug`,
    /// `.always`, or `.custom("FLAG")`. The associated value describes the
    /// offending argument.
    case invalidMacroArgument(String)
    /// An `@autoclosure` parameter whose own `throws`/`async` effect is not covered
    /// by the enclosing requirement. The associated value is the full explanation.
    case unsupportedAutoclosureEffect(String)
    /// A requirement whose name cannot be used to build the mock's tracking identifiers —
    /// an operator such as `==`, or a name that needs backtick escaping. The associated
    /// value is the full explanation.
    case unsupportedMemberName(String)
    /// An `init` requirement in a context the macro cannot yet mock: a protocol whose
    /// mock subclasses a parent protocol's mock. The associated value is the full
    /// explanation.
    case unsupportedInitializer(String)
    /// An `associatedtype` whose constraints the mock's `Any` fallback cannot satisfy.
    /// The associated value is the full explanation.
    case unsupportedAssociatedType(String)
    /// An inherited type the generated mock cannot be made to conform to — a protocol
    /// with requirements the macro cannot witness, or a parent protocol written with
    /// generic arguments. The associated value is the full explanation.
    case unsupportedInheritedType(String)
    /// A requirement whose return type mentions a generic parameter inside a function type,
    /// which the mock cannot rebuild from its erased handler result. The associated value is
    /// the full explanation.
    case unsupportedGenericReturn(String)
    /// A requirement with a closure parameter whose own parameters mention a generic
    /// parameter, which the mock cannot forward to its erased handler. The associated value
    /// is the full explanation.
    case unsupportedGenericParameter(String)

    /// The text shown at the diagnostic's source location. Cases carrying an
    /// explanation report it verbatim, so each diagnostic can describe why the
    /// requirement cannot be mocked in its own terms.
    var message: String {
        switch self {
        case .notAProtocol:
            return "@Mockable can only be applied to protocols"
        case .unsupportedMember(let member):
            return "Unsupported protocol member: \(member)"
        case .invalidMacroArgument(let message):
            return "Invalid @Mockable argument: \(message)"
        case .unsupportedAutoclosureEffect(let message):
            return message
        case .unsupportedMemberName(let message):
            return message
        case .unsupportedInitializer(let message):
            return message
        case .unsupportedAssociatedType(let message):
            return message
        case .unsupportedInheritedType(let message):
            return message
        case .unsupportedGenericReturn(let message):
            return message
        case .unsupportedGenericParameter(let message):
            return message
        }
    }

    /// Every case is an error: the alternative to reporting is an expansion that does
    /// not compile, so there is nothing a warning would let the build proceed with.
    var severity: DiagnosticSeverity { .error }

    /// The stable identifier tools use to group these diagnostics.
    var diagnosticID: MessageID {
        switch self {
        case .notAProtocol:
            return MessageID(domain: "MockableMacro", id: "notAProtocol")
        case .unsupportedMember:
            return MessageID(domain: "MockableMacro", id: "unsupportedMember")
        case .invalidMacroArgument:
            return MessageID(domain: "MockableMacro", id: "invalidMacroArgument")
        case .unsupportedAutoclosureEffect:
            return MessageID(domain: "MockableMacro", id: "unsupportedAutoclosureEffect")
        case .unsupportedMemberName:
            return MessageID(domain: "MockableMacro", id: "unsupportedMemberName")
        case .unsupportedInitializer:
            return MessageID(domain: "MockableMacro", id: "unsupportedInitializer")
        case .unsupportedAssociatedType:
            return MessageID(domain: "MockableMacro", id: "unsupportedAssociatedType")
        case .unsupportedInheritedType:
            return MessageID(domain: "MockableMacro", id: "unsupportedInheritedType")
        case .unsupportedGenericReturn:
            return MessageID(domain: "MockableMacro", id: "unsupportedGenericReturn")
        case .unsupportedGenericParameter:
            return MessageID(domain: "MockableMacro", id: "unsupportedGenericParameter")
        }
    }

    /// `CustomStringConvertible` conformance, mirroring the diagnostic message.
    var description: String { message }
}
