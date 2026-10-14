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
    /// mock's isolation and so cannot reach isolated tracking state. Swift infers the
    /// isolation of a witness from the requirement it satisfies: a `nonisolated`
    /// requirement of a `@MainActor` protocol gets a `nonisolated` witness, and a
    /// requirement with an `isolated` parameter gets a witness isolated to its
    /// argument — neither can read the mock's isolated stored properties. The
    /// protocol's own attributes are not consulted: the modifier only means something
    /// on an isolated protocol, and a protocol can inherit its isolation from a parent
    /// the macro cannot see.
    var hasRequirementsLeavingIsolation: Bool {
        collectDeclsIncludingConditional().contains { Self.leavesMockIsolation($0) }
    }

    /// Whether a requirement's witness takes an isolation other than the mock's: the
    /// requirement is declared `nonisolated`, or one of its parameters is `isolated`.
    static func leavesMockIsolation(_ decl: DeclSyntax) -> Bool {
        if let funcDecl = decl.as(FunctionDeclSyntax.self) {
            return isNonisolated(funcDecl.modifiers)
                || hasIsolatedParameter(funcDecl.signature.parameterClause.parameters)
        }

        if let initDecl = decl.as(InitializerDeclSyntax.self) {
            return hasIsolatedParameter(initDecl.signature.parameterClause.parameters)
        }

        if let varDecl = decl.as(VariableDeclSyntax.self) {
            return isNonisolated(varDecl.modifiers)
        }

        if let subscriptDecl = decl.as(SubscriptDeclSyntax.self) {
            return isNonisolated(subscriptDecl.modifiers)
                || hasIsolatedParameter(subscriptDecl.parameterClause.parameters)
        }

        return false
    }

    /// Whether a parameter list carries the `isolated` specifier, e.g.
    /// `func run(on actor: isolated any Actor)`.
    static func hasIsolatedParameter(_ parameters: FunctionParameterListSyntax) -> Bool {
        parameters.contains { parameter in
            specifiers(of: parameter.type).contains("isolated")
        }
    }

    /// Whether a modifier list marks a member `nonisolated`.
    static func isNonisolated(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { $0.name.text == "nonisolated" }
    }

    /// Whether a member's tracking state is lock-backed: every member of a
    /// `Sendable`/actor mock, plus every type member (shared across instances).
    func usesLockBasedStorage(isTypeMember: Bool) -> Bool {
        usesInstanceStorageLock || isTypeMember
    }
}
