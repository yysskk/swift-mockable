import SwiftSyntax

// MARK: - Tracking Identifiers

extension MockGenerator {
    /// The identifier every requirement's tracking members are named after, keyed by
    /// the declaration they belong to.
    ///
    /// Each requirement starts from the identifier its own kind suggests — a method's
    /// name, an overload's name plus a disambiguating suffix, `init`, `subscript` plus
    /// the index types — and those suggestions can coincide across requirements even
    /// though each is unique among its own kind. `func load(_ item: Item)` suggests
    /// `loadItem` because it is overloaded, and so does `func loadItem()` because that
    /// is its name, leaving the mock with two `loadItemCallCount` members. Assigning
    /// the identifiers together, rather than one requirement at a time, is what keeps
    /// them distinct.
    ///
    /// A requirement whose identifier is a name it declares keeps it: a property's
    /// identifier is the property itself, and a method's name is how its author refers
    /// to it. Only a suggestion that carries a generated suffix gives way, by
    /// continuing to count (`loadItem2`), so identifiers are unchanged for a protocol
    /// whose requirements do not collide.
    ///
    /// `decls` is the protocol's requirements flattened out of any conditional
    /// compilation, in declaration order, which the caller already has.
    func assignTrackingIdentifiers(
        in decls: [DeclSyntax],
        methodGroups: [String: [FunctionDeclSyntax]],
        initializers: [InitializerDeclSyntax],
        subscripts: [SubscriptDeclSyntax]
    ) -> [SyntaxIdentifier: String] {
        // Names the requirements declare themselves, which no other requirement may take.
        var taken = Set(decls.flatMap(Self.declaredIdentifiers))
        var suffixed: [(id: SyntaxIdentifier, suggestion: String)] = []
        var identifiers: [SyntaxIdentifier: String] = [:]

        for decl in decls {
            if let funcDecl = decl.as(FunctionDeclSyntax.self) {
                let suggestion = Self.suggestedIdentifier(for: funcDecl, in: methodGroups[funcDecl.name.text] ?? [])
                // A method that needed no suffix is tracked under its own name, which
                // is already reserved above.
                if suggestion == funcDecl.name.text {
                    identifiers[funcDecl.id] = suggestion
                } else {
                    suffixed.append((funcDecl.id, suggestion))
                }
            } else if let initDecl = decl.as(InitializerDeclSyntax.self) {
                suffixed.append((initDecl.id, Self.suggestedIdentifier(for: initDecl, in: initializers)))
            } else if let subscriptDecl = decl.as(SubscriptDeclSyntax.self) {
                suffixed.append((subscriptDecl.id, Self.suggestedIdentifier(for: subscriptDecl, in: subscripts)))
            }
        }

        for (id, suggestion) in suffixed {
            identifiers[id] = Self.unusedIdentifier(from: suggestion, avoiding: &taken)
        }

        return identifiers
    }

    /// The identifiers a declaration reserves by naming them: a property is tracked
    /// under its own name, and a method under its name unless it is overloaded.
    private static func declaredIdentifiers(of decl: DeclSyntax) -> [String] {
        if let funcDecl = decl.as(FunctionDeclSyntax.self) {
            return [funcDecl.name.text]
        }
        if let varDecl = decl.as(VariableDeclSyntax.self) {
            return varDecl.bindings.compactMap { $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text }
        }
        return []
    }

    /// The suggestion counted on until it is free, e.g. `loadItem` -> `loadItem2`.
    private static func unusedIdentifier(from suggestion: String, avoiding taken: inout Set<String>) -> String {
        var identifier = suggestion
        var ordinal = 1
        while taken.contains(identifier) {
            ordinal += 1
            identifier = "\(suggestion)\(ordinal)"
        }
        taken.insert(identifier)
        return identifier
    }

    // MARK: - Per-Kind Suggestions

    /// The identifier a method suggests: its name, plus a suffix disambiguating it from
    /// the protocol's other methods of that name.
    static func suggestedIdentifier(for funcDecl: FunctionDeclSyntax, in group: [FunctionDeclSyntax]) -> String {
        let suffix = group.count > 1 ? functionIdentifierSuffix(from: funcDecl, in: group) : ""
        return suffix.isEmpty ? funcDecl.name.text : "\(funcDecl.name.text)\(suffix)"
    }

    /// The identifier an initializer suggests: `init`, plus a suffix when the protocol
    /// declares more than one.
    static func suggestedIdentifier(for initDecl: InitializerDeclSyntax, in group: [InitializerDeclSyntax]) -> String {
        initializerIdentifier(for: initDecl, in: group)
    }

    /// The identifier a subscript suggests. Generated members cannot be named after a
    /// subscript's (absent) base name, so the suffix is always present.
    static func suggestedIdentifier(for subscriptDecl: SubscriptDeclSyntax, in group: [SubscriptDeclSyntax]) -> String {
        MockNaming.subscriptIdentifier(suffix: subscriptIdentifierSuffix(from: subscriptDecl, in: group))
    }
}
