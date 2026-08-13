import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Overload Identifier Suffixes

extension MockGenerator {
    /// Groups function declarations by their name, including conditional members.
    /// This is used to detect overloaded methods. Pass the protocol's flattened
    /// requirements when the caller already has them, to avoid re-walking the tree.
    func groupMethodsByNameIncludingConditional(
        in decls: [DeclSyntax]? = nil
    ) -> [String: [FunctionDeclSyntax]] {
        var methodGroups: [String: [FunctionDeclSyntax]] = [:]

        for decl in decls ?? collectDeclsIncludingConditional() {
            if let funcDecl = decl.as(FunctionDeclSyntax.self) {
                let funcName = funcDecl.name.text
                methodGroups[funcName, default: []].append(funcDecl)
            }
        }

        return methodGroups
    }

    /// All initializer requirements declared by the protocol, including those nested in
    /// conditional-compilation blocks. Used to detect `init` overloads and to decide
    /// whether the mock declares its own initializers.
    func collectInitializers() -> [InitializerDeclSyntax] {
        collectDeclsIncludingConditional().compactMap { $0.as(InitializerDeclSyntax.self) }
    }

    /// Whether the protocol declares at least one `init` requirement.
    var hasInitializerRequirements: Bool {
        collectDeclsIncludingConditional().contains { $0.is(InitializerDeclSyntax.self) }
    }

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
            let getterEffects = MockGenerator.effectfulSubscriptGetter(subscriptDecl)?.effectSpecifiers
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

        if let returnType = signature.returnType {
            let returnTypeName = returnType.trimmedDescription
            if returnTypeName != "Void" && returnTypeName != "()" {
                suffix += sanitizeTypeName(returnTypeName)
            }
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

    // MARK: - Function Identifier Suffix

    /// Generates a unique suffix based on parameter types to distinguish overloaded functions.
    /// Example: `func set(_ value: Bool, forKey: Key)` -> "BoolKey"
    static func functionIdentifierSuffix(from funcDecl: FunctionDeclSyntax) -> String {
        overloadBaseSuffix(parameters: funcDecl.signature.parameterClause.parameters)
    }

    /// Generates a unique suffix for an overloaded function within a group of methods
    /// with the same name. See `overloadSuffix(for:in:)` for the disambiguation stages.
    static func functionIdentifierSuffix(from funcDecl: FunctionDeclSyntax, in methodGroup: [FunctionDeclSyntax]) -> String {
        overloadSuffix(for: OverloadSignature(funcDecl), in: methodGroup.map(OverloadSignature.init))
    }

    // MARK: - Initializer Identifier Suffix

    /// Generates a suffix based on parameter types to distinguish overloaded initializers,
    /// mirroring `functionIdentifierSuffix(from:)`. Example: `init(host: String, port: Int)`
    /// -> "StringInt".
    static func initializerIdentifierSuffix(from initDecl: InitializerDeclSyntax) -> String {
        overloadBaseSuffix(parameters: initDecl.signature.parameterClause.parameters)
    }

    /// Generates a unique suffix for an overloaded initializer within a group of `init`
    /// requirements. See `overloadSuffix(for:in:)` for the disambiguation stages;
    /// initializers have no return type, so that disambiguator does not apply.
    static func initializerIdentifierSuffix(from initDecl: InitializerDeclSyntax, in group: [InitializerDeclSyntax]) -> String {
        overloadSuffix(for: OverloadSignature(initDecl), in: group.map(OverloadSignature.init))
    }

    // MARK: - Subscript Identifier Suffix

    /// Generates a unique suffix based on parameter types to distinguish overloaded subscripts.
    /// Unlike functions, the suffix is emitted even for a sole subscript, because generated
    /// members cannot be named after a subscript's missing base name.
    static func subscriptIdentifierSuffix(from subscriptDecl: SubscriptDeclSyntax) -> String {
        overloadBaseSuffix(parameters: subscriptDecl.parameterClause.parameters)
    }

    /// Generates a unique suffix for a subscript within the protocol's subscript group.
    /// See `overloadSuffix(for:in:)` for the disambiguation stages; a sole subscript
    /// keeps the plain parameter-type suffix.
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
