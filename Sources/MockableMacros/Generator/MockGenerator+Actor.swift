import SwiftSyntax

// MARK: - Actor-specific helpers

extension MockGenerator {
    /// Mock internals that are shared via lock-based storage are exposed as nonisolated
    /// so tests can inspect call counters/arguments without hopping to the mock's
    /// isolation. Every member of an actor mock qualifies; on a global-actor-isolated
    /// mock only the members of a `nonisolated` requirement do, because its witness is
    /// itself nonisolated and has to reach them.
    func storageBackedMemberModifiers(isNonisolated: Bool = false, isTypeMember: Bool = false) -> [DeclModifierSyntax] {
        // An actor's static members are already reachable from outside it, so only its
        // instance members need the modifier. On a global-actor-isolated class every
        // member is isolated, static ones included.
        if isActor {
            return isTypeMember ? [] : [DeclModifierSyntax(name: .keyword(.nonisolated))]
        }
        return isNonisolated ? [DeclModifierSyntax(name: .keyword(.nonisolated))] : []
    }
}
