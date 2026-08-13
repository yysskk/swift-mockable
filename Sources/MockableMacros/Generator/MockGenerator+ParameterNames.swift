import SwiftParser
import SwiftSyntax

// MARK: - Parameter Name Normalization

extension MockGenerator {
    /// The prefix of the internal names synthesized for parameters that have none.
    private static let synthesizedParameterNamePrefix = "param"

    /// Expression spellings that parse as a plain identifier reference but denote
    /// something else inside a type body, so a parameter of that name has to be
    /// referred to with backticks.
    private static let contextuallyBoundNames: Set<String> = ["self", "Self", "super"]

    /// Whether `text` refers to a parameter of that name when written as-is in the
    /// body of a generated member.
    ///
    /// Argument labels keep their source spelling but are lexed as identifiers even
    /// when they are keywords (SwiftParser remaps them), so the token kind cannot
    /// answer this. Parsing the text as an expression can: a name that needs escaping
    /// either fails to parse (`for`, `await`) or parses as something other than a
    /// plain identifier reference (`nil`, `true`, `_`). `self`, `Self`, and `super`
    /// do parse as identifier references but are bound by the enclosing type, so they
    /// are rejected explicitly. An already-escaped name (`` `repeat` ``) keeps its
    /// backticks in the token text and is referenceable as it stands.
    static func isBodyReferenceableName(_ text: String) -> Bool {
        guard !contextuallyBoundNames.contains(text) else {
            return false
        }

        var parser = Parser(text)
        let expression = ExprSyntax.parse(from: &parser)
        guard !expression.hasError,
              let reference = expression.as(DeclReferenceExprSyntax.self),
              reference.argumentNames == nil,
              reference.baseName.text == text else {
            return false
        }
        return true
    }

    /// The parameter's internal name with any backticks removed, which is the name it
    /// actually declares. Used to compare names for collisions.
    static func declaredParameterName(_ param: FunctionParameterSyntax) -> String {
        unescaped((param.secondName ?? param.firstName).text)
    }

    /// Removes the backticks of an escaped identifier, e.g. `` `repeat` `` -> `repeat`.
    private static func unescaped(_ text: String) -> String {
        guard text.count > 2, text.hasPrefix("`"), text.hasSuffix("`") else {
            return text
        }
        return String(text.dropFirst().dropLast())
    }

    /// Rewrites a parameter clause so every parameter has an internal name the generated
    /// bodies can refer to, leaving argument labels — and therefore every call site —
    /// untouched.
    ///
    /// A parameter without a usable internal name (`func handle(_: Event)`) gets a
    /// synthesized one, and a keyword name (`func value(for: Key)`) is escaped with
    /// backticks. Both are internal names, which take no part in protocol conformance,
    /// so the rewritten clause still satisfies the requirement. A clause whose
    /// parameters are all referenceable is returned unchanged, so an ordinary
    /// requirement is mocked exactly as before.
    static func parametersWithReferenceableNames(
        _ parameters: FunctionParameterListSyntax
    ) -> FunctionParameterListSyntax {
        guard parameters.contains(where: { !isBodyReferenceableName(($0.secondName ?? $0.firstName).text) }) else {
            return parameters
        }

        var takenNames = Set(parameters.map(declaredParameterName))

        let rewritten = parameters.enumerated().map { index, param -> FunctionParameterSyntax in
            let name = (param.secondName ?? param.firstName).text
            if isBodyReferenceableName(name) {
                return param
            }

            // A keyword name is a name; it only needs escaping. The wildcard `_` names
            // nothing, so the parameter needs a name of its own.
            if name == "_" {
                let synthesized = uniqueName(
                    startingAt: "\(synthesizedParameterNamePrefix)\(index)",
                    avoiding: &takenNames
                )
                return param.with(\.secondName, .identifier(synthesized, leadingTrivia: .space))
            }

            let escaped = TokenSyntax.identifier("`\(name)`")
            if param.secondName == nil {
                // The single name is both the label and the internal name. Escaping it
                // in place keeps the label spelling, so call sites are unaffected.
                return param.with(\.firstName, escaped.with(\.leadingTrivia, param.firstName.leadingTrivia))
            }
            return param.with(\.secondName, escaped.with(\.leadingTrivia, .space))
        }

        return FunctionParameterListSyntax(rewritten)
    }

    /// The first unused name at or after `candidate`, reserving it. Collisions are
    /// broken with a trailing underscore, which cannot collide with another
    /// synthesized name.
    private static func uniqueName(startingAt candidate: String, avoiding taken: inout Set<String>) -> String {
        var name = candidate
        while taken.contains(name) {
            name += "_"
        }
        taken.insert(name)
        return name
    }

    /// The names a witness body uses for its own locals and for the mock members it
    /// reads, chosen so that a requirement's parameters cannot capture either.
    ///
    /// A parameter is in scope throughout the body, so one named `storage` or
    /// `_handler` would shadow the locals the body binds, and one named after a
    /// generated member — `fetchCallCount` for `func fetch(fetchCallCount: Int)` —
    /// would shadow the member the body records into. Locals move out of the way;
    /// members cannot, so they are read through `self`/`Self` instead.
    struct WitnessNames {
        /// The handler bound from the mock's handler property.
        let handler: String
        /// The handler's result, bound when `inout` arguments have to be written back.
        let result: String
        /// The write-back value of a requirement that returns nothing.
        let writeBack: String
        /// The `withLock` closure's parameter on the lock-backed paths.
        let storage: String
        /// `""`, `"self."`, or `"Self."`: how the body refers to the mock's members.
        let memberPrefix: String

        /// Picks names that no parameter of the requirement declares. The defaults are
        /// kept whenever they are free, so an ordinary requirement's witness is
        /// generated exactly as before.
        init(parameters: FunctionParameterListSyntax, memberNames: [String] = [], isTypeMember: Bool = false) {
            let parameterNames = Set(parameters.map(MockGenerator.declaredParameterName))
            var taken = parameterNames

            self.handler = MockGenerator.uniqueName(startingAt: "_handler", avoiding: &taken)
            self.result = MockGenerator.uniqueName(startingAt: "_result", avoiding: &taken)
            self.writeBack = MockGenerator.uniqueName(startingAt: "_writeBack", avoiding: &taken)
            self.storage = MockGenerator.uniqueName(startingAt: "storage", avoiding: &taken)

            let shadowsMember = memberNames.contains { parameterNames.contains($0) }
            self.memberPrefix = shadowsMember ? (isTypeMember ? "Self." : "self.") : ""
        }

        /// The mock member `name` as the body should refer to it.
        func member(_ name: String) -> String {
            "\(memberPrefix)\(name)"
        }

        /// A further local name, chosen like the ones above so that neither a parameter
        /// nor an already-chosen local can capture it. Used for the accessor parameter
        /// of a subscript setter, which is only needed on the setter path.
        func uniqueLocalName(startingAt candidate: String, parameters: FunctionParameterListSyntax) -> String {
            var taken = Set(parameters.map(MockGenerator.declaredParameterName))
            taken.formUnion([handler, result, writeBack, storage])
            return MockGenerator.uniqueName(startingAt: candidate, avoiding: &taken)
        }
    }
}

/// Rewrites every requirement's parameter clause so the generated mock can refer to
/// its parameters, applied once to the protocol's member block.
///
/// Running this before anything reads the members keeps the witness signatures, the
/// recorded-argument types, and the generated bodies in agreement, and keeps the node
/// identities that overload disambiguation compares stable across those passes.
final class ParameterNameNormalizer: SyntaxRewriter {
    override func visit(_ node: FunctionParameterClauseSyntax) -> FunctionParameterClauseSyntax {
        node.with(\.parameters, MockGenerator.parametersWithReferenceableNames(node.parameters))
    }
}
