import SwiftSyntax

/// Represents Swift access level modifiers
enum AccessLevel: String {
    case `public` = "public"
    case `package` = "package"
    case `internal` = "internal"
    case `fileprivate` = "fileprivate"
    case `private` = "private"

    /// The keyword to use for the class/actor declaration
    var keyword: Keyword {
        switch self {
        case .public: return .public
        case .package: return .package
        case .internal: return .internal
        case .fileprivate: return .fileprivate
        case .private: return .private
        }
    }

    /// The keyword to use for members of the generated mock.
    /// For `private` protocols, members must be `fileprivate` to satisfy protocol requirements.
    var memberKeyword: Keyword {
        switch self {
        case .public: return .public
        case .package: return .package
        case .internal: return .internal
        case .fileprivate: return .fileprivate
        case .private: return .fileprivate  // Private protocol members must be fileprivate
        }
    }

    /// What a generated declaration is, which decides how the protocol's access level
    /// is spelled on it.
    enum DeclarationRole {
        /// The mock type itself.
        case mockType
        /// The mock type where other modules may subclass it: a `public` protocol's
        /// mock is declared `open`.
        case subclassableMockType
        /// A member of the mock. A `private` protocol's members are `fileprivate`,
        /// since that is the access a witness of its requirements needs.
        case member
        /// A member subclasses in other modules may override: a `public` protocol's
        /// is declared `open`.
        case overridableMember
    }

    /// The access modifier a generated declaration carries for `role`, or `nil` for
    /// `internal`, which is the default and needs no modifier.
    func modifier(for role: DeclarationRole) -> DeclModifierSyntax? {
        if self == .internal {
            return nil
        }

        let modifierKeyword: Keyword
        switch role {
        case .mockType:
            modifierKeyword = keyword
        case .subclassableMockType:
            modifierKeyword = self == .public ? .open : keyword
        case .member:
            modifierKeyword = memberKeyword
        case .overridableMember:
            modifierKeyword = self == .public ? .open : memberKeyword
        }

        return DeclModifierSyntax(name: .keyword(modifierKeyword))
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
