import Foundation

enum MockableError: Error, CustomStringConvertible {
    case notAProtocol
    case unsupportedMember(String)

    var description: String {
        switch self {
        case .notAProtocol:
            return "@Mockable can only be applied to protocols"
        case .unsupportedMember(let member):
            return "Unsupported protocol member: \(member)"
        }
    }
}
