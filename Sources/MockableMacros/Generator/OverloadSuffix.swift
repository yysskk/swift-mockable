import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Overload Identifier Suffixes

/// Builds the suffixes that tell overloaded requirements apart in their tracking
/// identifiers, e.g. `fetchInt` and `fetchString` for two `fetch` overloads.
///
/// Stateless: it reads syntax only, never the generator's state.
enum OverloadSuffix {
    /// The tracking identifier for an initializer within its overload group, e.g. `init`
    /// for a sole initializer or `initString` for an overload taking a `String`.
    static func initializerIdentifier(for initDecl: InitializerDeclSyntax, in group: [InitializerDeclSyntax]) -> String {
        let suffix = group.count > 1 ? initializerIdentifierSuffix(from: initDecl, in: group) : ""
        return MockNaming.initializerIdentifier(suffix: suffix)
    }

    // MARK: - Overload Disambiguation

    /// The signature facts overload disambiguation is computed from, extracted once so
    /// functions, initializers, and subscripts share a single suffix algorithm.
    private struct OverloadSignature {
        let id: SyntaxIdentifier
        let parameters: FunctionParameterListSyntax
        let isAsync: Bool
        let hasThrowsEffect: Bool
        /// `nil` for initializers, which have no return-type disambiguator.
        let returnType: TypeSyntax?

        init(_ funcDecl: FunctionDeclSyntax) {
            self.id = funcDecl.id
            self.parameters = funcDecl.signature.parameterClause.parameters
            self.isAsync = funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil
            self.hasThrowsEffect = funcDecl.signature.effectSpecifiers?.hasThrowsEffect == true
            self.returnType = funcDecl.signature.returnClause?.type
        }

        init(_ initDecl: InitializerDeclSyntax) {
            self.id = initDecl.id
            self.parameters = initDecl.signature.parameterClause.parameters
            self.isAsync = initDecl.signature.effectSpecifiers?.asyncSpecifier != nil
            self.hasThrowsEffect = initDecl.signature.effectSpecifiers?.hasThrowsEffect == true
            self.returnType = nil
        }

        init(_ subscriptDecl: SubscriptDeclSyntax) {
            let getterEffects = AccessorInspection.effectfulSubscriptGetter(subscriptDecl)?.effectSpecifiers
            self.id = subscriptDecl.id
            self.parameters = subscriptDecl.parameterClause.parameters
            self.isAsync = getterEffects?.asyncSpecifier != nil
            self.hasThrowsEffect = getterEffects?.hasThrowsEffect == true
            self.returnType = subscriptDecl.returnClause.type
        }
    }

    /// The suffix built from the parameter types alone, e.g. "BoolKey" for
    /// `(_ value: Bool, forKey: Key)`, or "" for an empty parameter list.
    private static func overloadBaseSuffix(parameters: FunctionParameterListSyntax) -> String {
        if parameters.isEmpty {
            return ""
        }

        return parameters
            .map { sanitizeTypeName($0.type.trimmedDescription) }
            .joined()
    }

    /// Extends a base suffix with the return type (functions only) and `Async`/`Throwing`
    /// markers to disambiguate overloads whose parameter types sanitize identically.
    /// A `rethrows` requirement counts as throwing here — the marker reflects the
    /// declared signature, unlike the handler closure, which drops `rethrows`.
    private static func extendedOverloadSuffix(for signature: OverloadSignature, baseSuffix: String) -> String {
        var suffix = baseSuffix

        // A requirement returning nothing contributes no return-type suffix, however it
        // spells `Void`.
        if let returnType = signature.returnType, DefaultReturnValue.returnsAValue(returnType) {
            suffix += sanitizeTypeName(returnType.trimmedDescription)
        }

        if signature.isAsync {
            suffix += "Async"
        }

        if signature.hasThrowsEffect {
            suffix += "Throwing"
        }

        return suffix
    }

    /// Disambiguates one overload within its group in three stages: parameter types
    /// first; then return type and `async`/`throws` markers when base suffixes collide;
    /// then a deterministic 1-based source-order ordinal when overloads still collide
    /// (e.g. nested generics that sanitize identically, such as `Foo<Bar, Baz>` and
    /// `Foo<BarBaz>`). The first colliding overload keeps the extended suffix for
    /// stability. Group membership is compared by node identity, so signatures must be
    /// built from the original declaration nodes.
    private static func overloadSuffix(for signature: OverloadSignature, in group: [OverloadSignature]) -> String {
        let baseSuffix = overloadBaseSuffix(parameters: signature.parameters)

        // Pair every group member with its base suffix once, rather than recomputing
        // it inside each collision filter.
        let membersWithBase = group.map { ($0, overloadBaseSuffix(parameters: $0.parameters)) }
        let baseCollisions = membersWithBase.filter { $0.1 == baseSuffix }
        if baseCollisions.count <= 1 {
            return baseSuffix
        }

        let extendedSuffix = extendedOverloadSuffix(for: signature, baseSuffix: baseSuffix)
        let extendedCollisions = baseCollisions.filter { member, memberBase in
            extendedOverloadSuffix(for: member, baseSuffix: memberBase) == extendedSuffix
        }
        guard extendedCollisions.count > 1 else {
            return extendedSuffix
        }

        guard let index = extendedCollisions.firstIndex(where: { $0.0.id == signature.id }), index > 0 else {
            return extendedSuffix
        }
        return "\(extendedSuffix)\(index + 1)"
    }

    /// The suffix built from the argument labels alone, e.g. "ForKey" for
    /// `(_ value: Bool, forKey key: Key)`, or "" when no parameter has a label. Each
    /// label is capitalized (see `capitalizedLabel(_:)`).
    private static func argumentLabelSuffix(parameters: FunctionParameterListSyntax) -> String {
        parameters
            .map(\.firstName)
            .filter { $0.tokenKind != .wildcard }
            .map { capitalizedLabel($0.text.trimmingBackticks) }
            .joined()
    }

    /// Acronyms that a label spells in lowercase when it starts with one, and that the
    /// Swift API Design Guidelines write in uppercase elsewhere in a name.
    private static let leadingAcronyms: Set<String> = [
        "api", "html", "http", "https", "id", "json", "ui", "uri", "url", "uuid", "xml",
    ]

    /// A label as it reads in the middle of an identifier: its first word capitalized,
    /// or uppercased when it is a common acronym, so that `fetch(id:)` gives "ID" and
    /// `load(urlString:)` gives "URLString", as the API Design Guidelines case
    /// acronyms; `forKey` gives "ForKey".
    static func capitalizedLabel(_ label: String) -> String {
        let firstWord = label.prefix { !$0.isUppercase && !$0.isNumber }
        if leadingAcronyms.contains(String(firstWord)) {
            return firstWord.uppercased() + label.dropFirst(firstWord.count)
        }
        return label.prefix(1).uppercased() + label.dropFirst()
    }

    /// Disambiguates one overload by its argument labels — the way Swift call sites
    /// tell overloads apart, as in `fetch(id:)` and `fetch(name:)` — and falls back to
    /// ``overloadSuffix(for:in:)`` among the overloads whose labels coincide, which
    /// have to differ in their types or effects instead.
    private static func labeledOverloadSuffix(for signature: OverloadSignature, in group: [OverloadSignature]) -> String {
        let labelSuffix = argumentLabelSuffix(parameters: signature.parameters)
        let labelCollisions = group.filter { argumentLabelSuffix(parameters: $0.parameters) == labelSuffix }
        guard labelCollisions.count > 1 else {
            return labelSuffix
        }
        return overloadSuffix(for: signature, in: labelCollisions)
    }

    // MARK: - Function Identifier Suffix

    /// Generates a unique suffix for an overloaded function within a group of methods
    /// with the same name: its argument labels, e.g. "ID" for `func fetch(id: Int)`, or
    /// its parameter types when another overload has the same labels, e.g. "Bool" for
    /// `func set(_ value: Bool)`. See `labeledOverloadSuffix(for:in:)`.
    static func functionIdentifierSuffix(from funcDecl: FunctionDeclSyntax, in methodGroup: [FunctionDeclSyntax]) -> String {
        labeledOverloadSuffix(for: OverloadSignature(funcDecl), in: methodGroup.map(OverloadSignature.init))
    }

    // MARK: - Initializer Identifier Suffix

    /// Generates a unique suffix for an overloaded initializer within a group of `init`
    /// requirements, disambiguated like a method's: "HostPort" for
    /// `init(host: String, port: Int)`, or the parameter types when another initializer
    /// has the same labels. Initializers have no return type, so that disambiguator
    /// does not apply. See `labeledOverloadSuffix(for:in:)`.
    static func initializerIdentifierSuffix(from initDecl: InitializerDeclSyntax, in group: [InitializerDeclSyntax]) -> String {
        labeledOverloadSuffix(for: OverloadSignature(initDecl), in: group.map(OverloadSignature.init))
    }

    // MARK: - Subscript Identifier Suffix

    /// Generates a unique suffix for a subscript within the protocol's subscript group.
    /// Unlike a function's, the suffix is emitted even for a sole subscript, because
    /// generated members cannot be named after a subscript's missing base name. It is
    /// built from the parameter types rather than argument labels: a subscript's
    /// parameters have no argument labels unless the declaration spells one out, so
    /// the index types are what tells subscripts apart. See `overloadSuffix(for:in:)`
    /// for the disambiguation stages; a sole subscript keeps the plain parameter-type
    /// suffix.
    static func subscriptIdentifierSuffix(from subscriptDecl: SubscriptDeclSyntax, in group: [SubscriptDeclSyntax]) -> String {
        overloadSuffix(for: OverloadSignature(subscriptDecl), in: group.map(OverloadSignature.init))
    }

    /// Sanitizes a type name for use in an identifier.
    /// Handles special characters, generics, optionals, and arrays.
    static func sanitizeTypeName(_ typeName: String) -> String {
        var result = typeName

        // Handle optional types
        if result.hasSuffix("?") {
            result = sanitizeTypeName(String(result.dropLast())) + "Optional"
            return result
        }

        // Handle implicitly unwrapped optionals
        if result.hasSuffix("!") {
            result = sanitizeTypeName(String(result.dropLast())) + "ImplicitlyUnwrapped"
            return result
        }

        // Handle array types [T]
        if result.hasPrefix("[") && result.hasSuffix("]") {
            let inner = String(result.dropFirst().dropLast())
            result = sanitizeTypeName(inner) + "Array"
            return result
        }

        // Handle generic types like Dictionary<K, V> or Array<T>
        if let openAngleIndex = result.firstIndex(of: "<"),
           let closeAngleIndex = result.lastIndex(of: ">") {
            let baseName = String(result[..<openAngleIndex])
            let genericArgsStr = String(result[result.index(after: openAngleIndex)..<closeAngleIndex])
            // Split generic arguments by comma, handling nested generics
            let genericArgs = splitGenericArguments(genericArgsStr)
            let sanitizedArgs = genericArgs.map { sanitizeTypeName(trimmingWhitespace($0)) }
            result = baseName + sanitizedArgs.joined()
        }

        // Remove any remaining special characters
        result = result.filter { $0.isLetter || $0.isNumber }

        // Ensure first letter is uppercase
        if let first = result.first {
            result = first.uppercased() + result.dropFirst()
        }

        return result
    }

    /// Removes leading and trailing whitespace from a string.
    private static func trimmingWhitespace(_ string: String) -> String {
        var substring = Substring(string)
        while substring.first?.isWhitespace == true {
            substring.removeFirst()
        }
        while substring.last?.isWhitespace == true {
            substring.removeLast()
        }
        return String(substring)
    }

    /// Splits generic arguments by comma, handling nested generics.
    /// E.g., "String, Dictionary<Int, String>" -> ["String", "Dictionary<Int, String>"]
    private static func splitGenericArguments(_ args: String) -> [String] {
        var result: [String] = []
        var current = ""
        var depth = 0

        for char in args {
            if char == "<" {
                depth += 1
                current.append(char)
            } else if char == ">" {
                depth -= 1
                current.append(char)
            } else if char == "," && depth == 0 {
                result.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }

        if !current.isEmpty {
            result.append(current)
        }

        return result
    }
}
