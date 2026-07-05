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
    /// `@Mockable` was given an argument; it does not accept any. The associated
    /// value describes the offending argument.
    case invalidMacroArgument(String)
    /// An `@autoclosure` parameter whose own `throws`/`async` effect is not covered
    /// by the enclosing requirement. The associated value is the full explanation.
    case unsupportedAutoclosureEffect(String)

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
        }
    }

    var severity: DiagnosticSeverity { .error }

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
        }
    }

    var description: String { message }
}
