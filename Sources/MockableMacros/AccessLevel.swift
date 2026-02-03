import SwiftSyntax

/// Represents Swift access level modifiers
enum AccessLevel: String {
    case `public` = "public"
    case `package` = "package"
    case `internal` = "internal"
    case `fileprivate` = "fileprivate"
    case `private` = "private"

    /// The keyword to use in generated code
    var keyword: Keyword {
        switch self {
        case .public: return .public
        case .package: return .package
        case .internal: return .internal
        case .fileprivate: return .fileprivate
        case .private: return .private
        }
    }

    /// Creates a DeclModifierSyntax for this access level.
    /// Returns nil for `internal` since it's the default and doesn't need explicit modifier.
    func makeModifier() -> DeclModifierSyntax? {
        // internal is the default, no modifier needed
        if self == .internal {
            return nil
        }
        return DeclModifierSyntax(name: .keyword(keyword))
    }

    /// Extracts the access level from a protocol declaration's modifiers
    static func from(protocolDecl: ProtocolDeclSyntax) -> AccessLevel {
        for modifier in protocolDecl.modifiers {
            switch modifier.name.tokenKind {
            case .keyword(.public):
                return .public
            case .keyword(.package):
                return .package
            case .keyword(.internal):
                return .internal
            case .keyword(.fileprivate):
                return .fileprivate
            case .keyword(.private):
                return .private
            default:
                continue
            }
        }
        // Default to internal if no explicit access modifier
        return .internal
    }
}
