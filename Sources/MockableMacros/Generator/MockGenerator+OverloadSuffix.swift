import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Overload Identifier Suffixes

extension MockGenerator {
    /// Groups function declarations by their name, including conditional members.
    /// This is used to detect overloaded methods.
    func groupMethodsByNameIncludingConditional() -> [String: [FunctionDeclSyntax]] {
        var methodGroups: [String: [FunctionDeclSyntax]] = [:]

        for decl in collectDeclsIncludingConditional() {
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

    // MARK: - Function Identifier Suffix

    /// Generates a unique suffix based on parameter types to distinguish overloaded functions.
    /// Example: `func set(_ value: Bool, forKey: Key)` -> "BoolKey"
    static func functionIdentifierSuffix(from funcDecl: FunctionDeclSyntax) -> String {
        let parameters = funcDecl.signature.parameterClause.parameters
        if parameters.isEmpty {
            return ""
        }

        let typeNames = parameters.map { param -> String in
            let typeName = param.type.trimmedDescription
            return sanitizeTypeName(typeName)
        }

        return typeNames.joined()
    }

    /// Generates a unique suffix for an overloaded function within a group of methods with the same name.
    /// First attempts to use parameter types only. If that results in duplicates within the group,
    /// adds return type and async/throws modifiers to disambiguate. If overloads still collide
    /// (e.g. nested generics that sanitize identically, such as `Foo<Bar, Baz>` and `Foo<BarBaz>`),
    /// a deterministic source-order ordinal is appended so generated names stay unique.
    static func functionIdentifierSuffix(from funcDecl: FunctionDeclSyntax, in methodGroup: [FunctionDeclSyntax]) -> String {
        let baseSuffix = functionIdentifierSuffix(from: funcDecl)

        // Check if there are duplicates with the same base suffix in the method group
        let baseCollisions = methodGroup.filter { functionIdentifierSuffix(from: $0) == baseSuffix }

        if baseCollisions.count <= 1 {
            // No duplicates, use base suffix
            return baseSuffix
        }

        // There are duplicates, add return type and async/throws to disambiguate
        let extendedSuffix = extendedFunctionIdentifierSuffix(from: funcDecl, baseSuffix: baseSuffix)

        let extendedCollisions = baseCollisions.filter {
            extendedFunctionIdentifierSuffix(from: $0, baseSuffix: functionIdentifierSuffix(from: $0)) == extendedSuffix
        }
        guard extendedCollisions.count > 1 else {
            return extendedSuffix
        }

        // Still colliding: append a deterministic 1-based ordinal by source order.
        // The first colliding overload keeps the extended suffix for stability.
        guard let index = extendedCollisions.firstIndex(where: { $0.id == funcDecl.id }), index > 0 else {
            return extendedSuffix
        }
        return "\(extendedSuffix)\(index + 1)"
    }

    /// Generates an extended suffix that includes return type and async/throws modifiers.
    private static func extendedFunctionIdentifierSuffix(from funcDecl: FunctionDeclSyntax, baseSuffix: String) -> String {
        var suffix = baseSuffix

        // Add return type if present and not Void
        if let returnClause = funcDecl.signature.returnClause {
            let returnTypeName = returnClause.type.trimmedDescription
            if returnTypeName != "Void" && returnTypeName != "()" {
                suffix += sanitizeTypeName(returnTypeName)
            }
        }

        // Add async modifier
        if funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil {
            suffix += "Async"
        }

        // Add throws modifier
        if funcDecl.signature.effectSpecifiers?.hasThrowsEffect == true {
            suffix += "Throwing"
        }

        return suffix
    }

    // MARK: - Initializer Identifier Suffix

    /// Generates a suffix based on parameter types to distinguish overloaded initializers,
    /// mirroring `functionIdentifierSuffix(from:)`. Example: `init(host: String, port: Int)`
    /// -> "StringInt".
    static func initializerIdentifierSuffix(from initDecl: InitializerDeclSyntax) -> String {
        let parameters = initDecl.signature.parameterClause.parameters
        if parameters.isEmpty {
            return ""
        }

        return parameters
            .map { sanitizeTypeName($0.type.trimmedDescription) }
            .joined()
    }

    /// Generates a unique suffix for an overloaded initializer within a group of `init`
    /// requirements. Mirrors the function overload logic: parameter types first, then
    /// `async`/`throws` modifiers, then a deterministic source-order ordinal if overloads
    /// still collide. Initializers have no return type, so that disambiguator does not apply.
    static func initializerIdentifierSuffix(from initDecl: InitializerDeclSyntax, in group: [InitializerDeclSyntax]) -> String {
        let baseSuffix = initializerIdentifierSuffix(from: initDecl)

        let baseCollisions = group.filter { initializerIdentifierSuffix(from: $0) == baseSuffix }
        if baseCollisions.count <= 1 {
            return baseSuffix
        }

        let extendedSuffix = extendedInitializerIdentifierSuffix(from: initDecl, baseSuffix: baseSuffix)
        let extendedCollisions = baseCollisions.filter {
            extendedInitializerIdentifierSuffix(from: $0, baseSuffix: initializerIdentifierSuffix(from: $0)) == extendedSuffix
        }
        guard extendedCollisions.count > 1 else {
            return extendedSuffix
        }

        // Still colliding: append a deterministic 1-based ordinal by source order. The first
        // colliding overload keeps the extended suffix for stability.
        guard let index = extendedCollisions.firstIndex(where: { $0.id == initDecl.id }), index > 0 else {
            return extendedSuffix
        }
        return "\(extendedSuffix)\(index + 1)"
    }

    /// Extends an initializer suffix with `async`/`throws` modifiers to disambiguate overloads
    /// whose parameter types sanitize identically.
    private static func extendedInitializerIdentifierSuffix(from initDecl: InitializerDeclSyntax, baseSuffix: String) -> String {
        var suffix = baseSuffix

        if initDecl.signature.effectSpecifiers?.asyncSpecifier != nil {
            suffix += "Async"
        }

        if initDecl.signature.effectSpecifiers?.hasThrowsEffect == true {
            suffix += "Throwing"
        }

        return suffix
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
