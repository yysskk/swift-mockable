import SwiftSyntax

/// Whether a requirement belongs to each instance of the conforming type or to the
/// type itself (`static`, or the `class` spelling protocols use for class-only
/// requirements).
///
/// The scope decides where a requirement's tracking state lives — type state is shared
/// by every instance, so it is always lock-backed, in its own `StaticStorage` struct —
/// and how the generated members and bodies spell it (`static`, `Self.`).
enum MemberScope {
    case instance
    case type

    /// The modifiers a generated member needs to mirror the requirement: `static` for
    /// a type member, nothing for an instance member. The mock always spells it
    /// `static`, even for a `class` requirement, since its own members are never
    /// overridden.
    var modifiers: [DeclModifierSyntax] {
        switch self {
        case .instance:
            return []
        case .type:
            return [DeclModifierSyntax(name: .keyword(.static))]
        }
    }
}
