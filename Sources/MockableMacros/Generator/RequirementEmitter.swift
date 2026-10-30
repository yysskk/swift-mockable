import SwiftSyntax

// MARK: - Requirement Emitters

/// Generates the mock's members for one kind of protocol requirement.
///
/// Each kind of requirement the mock witnesses — a method, an initializer, a property,
/// a subscript — has one emitter, which owns everything the mock declares for it: the
/// tracking requirements its slots are derived from, and the members that witness it.
/// The storage structs and `resetMock()` read the same tracking requirements, so they
/// need no knowledge of the kinds.
///
/// ``MockGenerator/emitter(for:)`` is the one place generation dispatches on the kind
/// of a requirement, so mocking a new kind of requirement means adding an emitter and a
/// case there. Diagnostics stay in `ProtocolValidator`, whose rules run before any
/// emitter is built.
protocol RequirementEmitter {
    /// The tracking requirements of the requirement: one per method, initializer, or
    /// subscript, and one per property binding.
    var trackingRequirements: [TrackingRequirement] { get }

    /// The mock members that witness the requirement and hold its tracking state, in
    /// emission order.
    func members() -> [MemberBlockItemSyntax]
}

extension MockGenerator {
    /// The emitter of a requirement, or `nil` for a member the mock declares no witness
    /// for: associated types and type aliases are emitted ahead of the other members
    /// (see `generateAssociatedTypeMembers`), and an unsupported member never reaches
    /// generation, since diagnostics reject the protocol first.
    ///
    /// Must be handed a requirement built from the original declaration nodes in
    /// `members` — overload ordinals compare node identity, so a re-parsed copy would
    /// break the `...2` suffixes.
    func emitter(for requirement: Requirement) -> (any RequirementEmitter)? {
        switch requirement {
        case .function(let funcDecl):
            return FunctionEmitter(generator: self, decl: funcDecl, requirement: requirement)
        case .initializer(let initDecl):
            return InitializerEmitter(generator: self, decl: initDecl)
        case .variable(let varDecl):
            return VariableEmitter(generator: self, decl: varDecl, requirement: requirement)
        case .subscript(let subscriptDecl):
            return SubscriptEmitter(generator: self, decl: subscriptDecl, requirement: requirement)
        case .associatedType, .typeAlias, .unsupported:
            return nil
        }
    }

    /// The tracking requirements declared by one protocol requirement, and none for a
    /// type declaration (see ``emitter(for:)``).
    func trackingRequirements(for requirement: Requirement) -> [TrackingRequirement] {
        emitter(for: requirement)?.trackingRequirements ?? []
    }
}
