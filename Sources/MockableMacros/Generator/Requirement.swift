import SwiftSyntax

/// One member of a `@Mockable` protocol, classified by what the mock has to do with it.
///
/// Every pass over the protocol reads its members through this type and switches over
/// the cases: diagnostics, overload grouping, tracking-identifier assignment, the
/// storage-model analyses, member generation, and `resetMock()`. A member kind the
/// mock has to treat specially is therefore handled in every pass, or the build fails
/// where it is not, instead of silently falling through an `if let` chain.
///
/// The cases wrap the declaration nodes exactly as they appear in the protocol's member
/// block. Overload disambiguation compares node identity, so a requirement must be built
/// from the original node rather than from a re-parsed copy.
enum Requirement {
    case function(FunctionDeclSyntax)
    case initializer(InitializerDeclSyntax)
    /// A property declaration, which may bind several names.
    case variable(VariableDeclSyntax)
    case `subscript`(SubscriptDeclSyntax)
    case associatedType(AssociatedTypeDeclSyntax)
    case typeAlias(TypeAliasDeclSyntax)
    /// A member the macro cannot mock at all, such as a nested type or an operator
    /// declaration. Reported by diagnostics; generation never sees one.
    case unsupported(DeclSyntax)

    /// Classifies a member declaration. A conditional-compilation block is not a
    /// requirement; see ``all(in:)`` for reading the members of every clause.
    init(_ decl: DeclSyntax) {
        if let functionDecl = decl.as(FunctionDeclSyntax.self) {
            self = .function(functionDecl)
        } else if let initializerDecl = decl.as(InitializerDeclSyntax.self) {
            self = .initializer(initializerDecl)
        } else if let variableDecl = decl.as(VariableDeclSyntax.self) {
            self = .variable(variableDecl)
        } else if let subscriptDecl = decl.as(SubscriptDeclSyntax.self) {
            self = .subscript(subscriptDecl)
        } else if let associatedTypeDecl = decl.as(AssociatedTypeDeclSyntax.self) {
            self = .associatedType(associatedTypeDecl)
        } else if let typeAliasDecl = decl.as(TypeAliasDeclSyntax.self) {
            self = .typeAlias(typeAliasDecl)
        } else {
            self = .unsupported(decl)
        }
    }

    /// The declaration as written in the protocol.
    var decl: DeclSyntax {
        switch self {
        case .function(let decl):
            return DeclSyntax(decl)
        case .initializer(let decl):
            return DeclSyntax(decl)
        case .variable(let decl):
            return DeclSyntax(decl)
        case .subscript(let decl):
            return DeclSyntax(decl)
        case .associatedType(let decl):
            return DeclSyntax(decl)
        case .typeAlias(let decl):
            return DeclSyntax(decl)
        case .unsupported(let decl):
            return decl
        }
    }

    /// Whether the requirement belongs to the type or to each instance. Only functions,
    /// properties, and subscripts can be type members; a `static subscript` is rejected
    /// by diagnostics before generation.
    var scope: MemberScope {
        switch self {
        case .function(let decl):
            return decl.modifiers.declaresTypeMember ? .type : .instance
        case .variable(let decl):
            return decl.modifiers.declaresTypeMember ? .type : .instance
        case .subscript(let decl):
            return decl.modifiers.declaresTypeMember ? .type : .instance
        case .initializer, .associatedType, .typeAlias, .unsupported:
            return .instance
        }
    }

    /// Whether the requirement's witness takes an isolation other than the mock's: the
    /// requirement is declared `nonisolated`, or one of its parameters is `isolated`.
    ///
    /// Swift infers the isolation of a witness from the requirement it satisfies: a
    /// `nonisolated` requirement of a `@MainActor` protocol gets a `nonisolated`
    /// witness, and a requirement with an `isolated` parameter gets a witness isolated
    /// to its argument. Neither can read the mock's isolated stored properties, so the
    /// tracking state such a witness reaches has to live behind a lock. The protocol's
    /// own attributes are not consulted: the modifier only means something on an
    /// isolated protocol, and a protocol can inherit its isolation from a parent the
    /// macro cannot see.
    var leavesMockIsolation: Bool {
        switch self {
        case .function(let decl):
            return decl.modifiers.isNonisolated
                || decl.signature.parameterClause.parameters.hasIsolatedParameter
        case .initializer(let decl):
            return decl.signature.parameterClause.parameters.hasIsolatedParameter
        case .variable(let decl):
            return decl.modifiers.isNonisolated
        case .subscript(let decl):
            return decl.modifiers.isNonisolated
                || decl.parameterClause.parameters.hasIsolatedParameter
        case .associatedType, .typeAlias, .unsupported:
            return false
        }
    }

    /// Every requirement declared in a member block, flattened out of any
    /// conditional-compilation blocks, in declaration order.
    ///
    /// Every clause is read, `#else` included: the mock declares the members of all of
    /// them, each under its own condition, so requirements in sibling clauses share one
    /// namespace and have to be grouped, disambiguated, and diagnosed together.
    /// Flattening loses the `#if` structure, so this is for analysis; generation goes
    /// through the `map*PreservingIfConfig` drivers of `MockGenerator`, which keep it.
    static func all(in members: MemberBlockItemListSyntax) -> [Requirement] {
        var requirements: [Requirement] = []

        for member in members {
            if let ifConfigDecl = member.decl.as(IfConfigDeclSyntax.self) {
                requirements.append(contentsOf: all(in: ifConfigDecl))
            } else {
                requirements.append(Requirement(member.decl))
            }
        }

        return requirements
    }

    /// The requirements of every `.decls` clause of a conditional-compilation block.
    static func all(in ifConfigDecl: IfConfigDeclSyntax) -> [Requirement] {
        ifConfigDecl.clauses.flatMap { clause -> [Requirement] in
            guard let elements = clause.elements,
                  case .decls(let decls) = elements else {
                return []
            }
            return all(in: decls)
        }
    }
}

extension DeclModifierListSyntax {
    /// Whether the modifiers mark a type member: `static`, or the `class` spelling
    /// protocols use for class-only requirements.
    var declaresTypeMember: Bool {
        contains { modifier in
            let name = modifier.name.text
            return name == "static" || name == "class"
        }
    }

    /// Whether the modifiers mark the member `nonisolated`.
    var isNonisolated: Bool {
        contains { $0.name.text == "nonisolated" }
    }
}

extension FunctionParameterListSyntax {
    /// Whether a parameter carries the `isolated` specifier, as in
    /// `func run(on actor: isolated any Actor)`.
    var hasIsolatedParameter: Bool {
        contains { parameter in
            TypeErasure.specifiers(of: parameter.type).contains("isolated")
        }
    }
}
