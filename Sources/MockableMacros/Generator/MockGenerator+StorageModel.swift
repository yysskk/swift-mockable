import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Storage Model

extension MockGenerator {
    /// Whether the protocol declares any `static`/`class` requirement, and so needs a
    /// `StaticStorage` struct. Static tracking state is shared by every instance, so it
    /// is always lock-backed, even in a non-`Sendable` mock.
    func hasTypeMembers() -> Bool {
        collectRequirements().contains(where: \.isTypeMember)
    }

    /// The modifiers a generated member needs to mirror a type member: `static`, or
    /// nothing for an instance member. The mock always spells it `static`, even for a
    /// `class` requirement, since the mock's own members are never overridden.
    static func typeMemberModifiers(isTypeMember: Bool) -> [DeclModifierSyntax] {
        guard isTypeMember else {
            return []
        }

        return [DeclModifierSyntax(name: .keyword(.static))]
    }

    /// Whether the mock's instance tracking state is lock-backed. `Sendable` mocks need
    /// it to be safe to mutate across threads; actor mocks and global-actor-isolated
    /// mocks with a member outside their isolation need it because such a member cannot
    /// touch isolated state.
    var usesInstanceStorageLock: Bool {
        isActor || isSendable || needsNonisolatedStorage
    }

    /// Whether a member of a global-actor-isolated mock has to reach the tracking state
    /// from outside the mock's isolation, so the state is kept behind a `nonisolated`
    /// lock: the witness of a requirement that leaves the mock's isolation, or the
    /// `resetMock()` override of a mock subclassing a parent mock. An override takes the isolation of the
    /// method it overrides, and the macro cannot see whether the parent protocol is
    /// isolated — a `@MainActor` mock of a child of a nonisolated protocol gets a
    /// nonisolated `resetMock()`, which could not clear isolated stored properties.
    var needsNonisolatedStorage: Bool {
        hasRequirementsLeavingIsolation || (isGlobalActorIsolated && hasParentMock)
    }

    /// Whether the protocol declares a requirement whose witness cannot assume the
    /// mock's isolation and so cannot reach isolated tracking state (see
    /// `Requirement.leavesMockIsolation`).
    var hasRequirementsLeavingIsolation: Bool {
        collectRequirements().contains(where: \.leavesMockIsolation)
    }

    /// Whether a member's tracking state is lock-backed: every member of a
    /// `Sendable`/actor mock, plus every type member (shared across instances).
    func usesLockBasedStorage(isTypeMember: Bool) -> Bool {
        usesInstanceStorageLock || isTypeMember
    }
}
