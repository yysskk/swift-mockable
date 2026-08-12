import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Accessor Inspection

extension MockGenerator {
    /// Whether an accessor block declares a get-only requirement. `defaultWhenAbsent`
    /// decides the missing-block case, which properties and subscripts read differently:
    /// a subscript requirement with no block (`subscript(i: Int) -> Int`) is get-only,
    /// while a property binding with no block is not treated as one.
    static func isGetOnly(_ accessorBlock: AccessorBlockSyntax?, defaultWhenAbsent: Bool) -> Bool {
        guard let accessorBlock else {
            return defaultWhenAbsent
        }

        switch accessorBlock.accessors {
        case .getter:
            return true
        case .accessors(let accessors):
            let hasGetter = accessors.contains { $0.accessorSpecifier.tokenKind == .keyword(.get) }
            let hasSetter = accessors.contains { $0.accessorSpecifier.tokenKind == .keyword(.set) }
            return hasGetter && !hasSetter
        }
    }

    /// The `get` accessor of a block when it carries `async`/`throws` effects
    /// (e.g. `{ get async throws }`), or `nil` otherwise. A requirement with an
    /// effectful getter cannot have a setter (SE-0310).
    static func effectfulGetAccessor(in accessorBlock: AccessorBlockSyntax?) -> AccessorDeclSyntax? {
        guard let accessorBlock,
              case .accessors(let accessors) = accessorBlock.accessors else {
            return nil
        }
        return accessors.first { accessor in
            accessor.accessorSpecifier.tokenKind == .keyword(.get) && accessor.effectSpecifiers != nil
        }
    }

    /// The `" async"` / `" throws"` suffix appended to a handler closure type.
    static func effectsSuffix(isAsync: Bool, isThrows: Bool) -> String {
        var suffix = ""
        if isAsync {
            suffix += " async"
        }
        if isThrows {
            suffix += " throws"
        }
        return suffix
    }

    /// The effects suffix for an accessor's `async`/`throws` specifiers. The handler
    /// is untyped-throwing even for a typed-throws accessor (`get throws(E)`) — the
    /// generated getter re-throws the typed error via a `catch` — so a typed error
    /// type is dropped here.
    static func effectsSuffix(for effects: AccessorEffectSpecifiersSyntax?) -> String {
        effectsSuffix(
            isAsync: effects?.asyncSpecifier != nil,
            isThrows: effects?.hasThrowsEffect == true
        )
    }
}
