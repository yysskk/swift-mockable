import SwiftSyntax

// MARK: - Actor-specific helpers

extension MockGenerator {
    /// Actor mock internals that are shared via lock-based storage are exposed as nonisolated
    /// so tests can inspect call counters/arguments without actor hops.
    func storageBackedMemberModifiers() -> [DeclModifierSyntax] {
        guard isActor else {
            return []
        }
        return [DeclModifierSyntax(name: .keyword(.nonisolated))]
    }
}
