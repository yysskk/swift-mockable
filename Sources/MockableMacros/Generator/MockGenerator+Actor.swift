import SwiftSyntax

// MARK: - Actor-specific helpers

extension MockGenerator {
    /// Mock internals that are shared via lock-based storage are exposed as nonisolated
    /// so tests can inspect call counters/arguments without hopping to the mock's
    /// isolation. Every member of an actor mock qualifies; on a global-actor-isolated
    /// mock only the members of a requirement whose witness leaves the mock's isolation
    /// do — a `nonisolated` one, or one with an `isolated` parameter — because that
    /// witness has to reach them.
    func storageBackedMemberModifiers(leavesMockIsolation: Bool, scope: MemberScope) -> [DeclModifierSyntax] {
        // An actor's static members are already reachable from outside it, so only its
        // instance members need the modifier. On a global-actor-isolated class every
        // member is isolated, static ones included.
        if shape.isActor {
            return scope == .type ? [] : [DeclModifierSyntax(name: .keyword(.nonisolated))]
        }
        return leavesMockIsolation ? [DeclModifierSyntax(name: .keyword(.nonisolated))] : []
    }
}
