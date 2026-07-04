import SwiftDiagnostics

enum MockableError: Error, CustomStringConvertible, DiagnosticMessage {
    case notAProtocol
    case unsupportedMember(String)
    case invalidMacroArgument(String)
    case rethrowsRequirementNotSupported

    var message: String {
        switch self {
        case .notAProtocol:
            return "@Mockable can only be applied to protocols"
        case .unsupportedMember(let member):
            return "Unsupported protocol member: \(member)"
        case .invalidMacroArgument(let message):
            return "Invalid @Mockable argument: \(message)"
        case .rethrowsRequirementNotSupported:
            return "'rethrows' requirements are not supported by @Mockable; declare the requirement as 'throws' instead"
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
        case .rethrowsRequirementNotSupported:
            return MessageID(domain: "MockableMacro", id: "rethrowsRequirementNotSupported")
        }
    }

    var description: String { message }
}
