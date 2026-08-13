import SwiftSyntax

// MARK: - Actor-specific helpers

extension MockGenerator {
    /// Mock internals that are shared via lock-based storage are exposed as nonisolated
    /// so tests can inspect call counters/arguments without hopping to the mock's
    /// isolation. Every member of an actor mock qualifies; on a global-actor-isolated
    /// mock only the members of a `nonisolated` requirement do, because its witness is
    /// itself nonisolated and has to reach them.
    func storageBackedMemberModifiers(isNonisolated: Bool = false) -> [DeclModifierSyntax] {
        guard isActor || isNonisolated else {
            return []
        }
        return [DeclModifierSyntax(name: .keyword(.nonisolated))]
    }
}
