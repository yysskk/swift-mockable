import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Storage Model

extension MockGenerator {
    /// Whether the protocol declares any `static`/`class` requirement, and so needs a
    /// `StaticStorage` struct. Static tracking state is shared by every instance, so it
    /// is always lock-backed, even in a non-`Sendable` mock.
    func hasTypeMembers() -> Bool {
        collectDeclsIncludingConditional().contains { Self.isTypeMember($0) }
    }

    /// Whether a member declaration is a type member. Only functions, properties, and
    /// subscripts can be; `static subscript` is rejected by diagnostics before generation.
    static func isTypeMember(_ decl: DeclSyntax) -> Bool {
        if let funcDecl = decl.as(FunctionDeclSyntax.self) {
            return isTypeMember(funcDecl.modifiers)
        }

        if let varDecl = decl.as(VariableDeclSyntax.self) {
            return isTypeMember(varDecl.modifiers)
        }

        if let subscriptDecl = decl.as(SubscriptDeclSyntax.self) {
            return isTypeMember(subscriptDecl.modifiers)
        }

        return false
    }

    /// Whether a modifier list marks a type member (`static` or the `class` spelling
    /// protocols use for class-only requirements).
    static func isTypeMember(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { modifier in
            let modifierName = modifier.name.text
            return modifierName == "static" || modifierName == "class"
        }
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

    /// The lock-backed storage property a member's tracking state lives in:
    /// `_staticStorage` for type members, `_storage` for instance members.
    static func storagePropertyName(isTypeMember: Bool) -> String {
        MockNaming.storageName(isTypeMember: isTypeMember)
    }

    /// Whether the mock's instance tracking state is lock-backed. `Sendable` mocks need
    /// it to be safe to mutate across threads; actor mocks need it because their
    /// `nonisolated` tracking members cannot touch actor-isolated state.
    var usesInstanceStorageLock: Bool {
        isActor || isSendable
    }

    /// Whether a member's tracking state is lock-backed: every member of a
    /// `Sendable`/actor mock, plus every type member (shared across instances).
    func usesLockBasedStorage(isTypeMember: Bool) -> Bool {
        usesInstanceStorageLock || isTypeMember
    }
}
