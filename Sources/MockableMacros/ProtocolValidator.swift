import SwiftSyntax

/// The checks a protocol has to pass before a mock is generated for it.
///
/// Each check is a rule: a function from one requirement to the findings it reports.
/// The rules run in a fixed order and stop at the first rule that reports something
/// for a requirement, so a requirement that fails several checks is reported for the
/// most fundamental one. Adding a check means adding a rule to ``requirementRules``;
/// the protocol-level checks (the inheritance clause, and `init` requirements on an
/// inheriting protocol) read the shape and run after the rules.
enum ProtocolValidator {
    /// One reason the protocol cannot be mocked, located at the node it is reported on.
    struct Finding {
        let node: Syntax
        let diagnostic: MockableDiagnostic

        init(_ diagnostic: MockableDiagnostic, at node: some SyntaxProtocol) {
            self.node = Syntax(node)
            self.diagnostic = diagnostic
        }
    }

    /// A check over one requirement, reporting the findings that prevent it from
    /// being mocked.
    typealias RequirementRule = @Sendable (Requirement) -> [Finding]

    /// The per-requirement checks, in the order they are tried.
    static var requirementRules: [RequirementRule] {
        [
            unsupportedKind,
            unsupportedName,
            uncoveredAutoclosureEffects,
            genericFunctionTypeReturn,
            genericClosureParameters,
            constrainedAssociatedType,
        ]
    }

    /// Everything that prevents the protocol from being mocked, in the order it is
    /// reported: the requirements in declaration order (every conditional-compilation
    /// clause included, so one expansion surfaces every problem), then the inheritance
    /// clause, then `init` requirements the mock cannot chain to a parent mock.
    static func findings(in shape: ProtocolShape, members: MemberBlockItemListSyntax) -> [Finding] {
        let requirements = Requirement.all(in: members)
        var findings = requirements.flatMap(findings(for:))

        findings += shape.unsupportedInheritedTypes.map { inherited in
            Finding(.unsupportedInheritedType(name: inherited.name, reason: inherited.reason), at: inherited.type)
        }

        // An `init` declared directly on a protocol whose mock subclasses another is not
        // yet mockable: the witness would need to chain through the parent mock's
        // initializer, which the macro cannot see. Initializers inherited from the parent
        // still work, since the child mock inherits the parent mock's `required init`.
        if shape.subclassesParentMock {
            for case .initializer(let initDecl) in requirements {
                findings.append(Finding(.unsupportedInitializer, at: initDecl))
            }
        }

        return findings
    }

    /// The findings of the first rule that reports anything for `requirement`.
    static func findings(for requirement: Requirement) -> [Finding] {
        for rule in requirementRules {
            let findings = rule(requirement)
            if !findings.isEmpty {
                return findings
            }
        }
        return []
    }

    // MARK: - Rules

    /// A member kind the macro cannot mock at all: a nested type, an operator
    /// declaration, a `static subscript` (which has no storage to track). Reported
    /// rather than silently dropped from the mock.
    static func unsupportedKind(_ requirement: Requirement) -> [Finding] {
        switch requirement {
        case .subscript(let subscriptDecl) where requirement.scope == .type:
            return [Finding(.unsupportedMember(member: subscriptDecl.trimmedDescription), at: subscriptDecl)]
        case .unsupported(let decl):
            return [Finding(.unsupportedMember(member: decl.trimmedDescription), at: decl)]
        case .function, .initializer, .variable, .subscript, .associatedType, .typeAlias:
            return []
        }
    }

    /// A requirement whose name cannot be mocked. Generated members are named after the
    /// requirement — a method's tracking members append a suffix (`fetch` becomes
    /// `fetchCallCount`) and a property's backing storage takes a prefix (`name` becomes
    /// `_name`) — so a name that is not a plain identifier, such as an operator or a
    /// name written with backticks, would only produce illegal identifiers. A `var`
    /// may bind several names; bindings the generator skips (those without a plain
    /// identifier pattern) are skipped here too.
    static func unsupportedName(_ requirement: Requirement) -> [Finding] {
        switch requirement {
        case .function(let functionDecl):
            return unsupportedName(functionDecl.name, of: functionDecl).map { [$0] } ?? []
        case .variable(let variableDecl):
            return variableDecl.bindings.compactMap { binding in
                guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier else {
                    return nil
                }
                return unsupportedName(identifier, of: variableDecl)
            }
        case .initializer, .subscript, .associatedType, .typeAlias, .unsupported:
            return []
        }
    }

    private static func unsupportedName(_ name: TokenSyntax, of node: some SyntaxProtocol) -> Finding? {
        let isOperator: Bool
        switch name.tokenKind {
        case .identifier(let text) where !text.contains("`"):
            return nil
        case .binaryOperator, .prefixOperator, .postfixOperator:
            isOperator = true
        default:
            isOperator = false
        }
        return Finding(.unsupportedMemberName(name: name.text, isOperator: isOperator), at: node)
    }

    /// An `@autoclosure` parameter whose own effects (`throws`/`async`) are not covered
    /// by the enclosing requirement. The generated witness evaluates autoclosure
    /// arguments once per call to record them, which is only possible when the
    /// surrounding member can apply `try`/`await`; a subscript can apply neither.
    static func uncoveredAutoclosureEffects(_ requirement: Requirement) -> [Finding] {
        let parameters: FunctionParameterListSyntax
        let effects: FunctionEffectSpecifiersSyntax?
        let inSubscript: Bool
        switch requirement {
        case .function(let functionDecl):
            parameters = functionDecl.signature.parameterClause.parameters
            effects = functionDecl.signature.effectSpecifiers
            inSubscript = false
        case .initializer(let initDecl):
            parameters = initDecl.signature.parameterClause.parameters
            effects = initDecl.signature.effectSpecifiers
            inSubscript = false
        case .subscript(let subscriptDecl):
            parameters = subscriptDecl.parameterClause.parameters
            effects = nil
            inSubscript = true
        case .variable, .associatedType, .typeAlias, .unsupported:
            return []
        }

        let coversThrows = effects?.hasThrowsEffect ?? false
        let coversAsync = effects?.asyncSpecifier != nil

        return parameters.compactMap { parameter in
            guard let functionType = MockGenerator.autoclosureFunctionType(of: parameter) else {
                return nil
            }
            var uncoveredEffects: [String] = []
            if functionType.effectSpecifiers?.hasThrowsEffect ?? false, !coversThrows {
                uncoveredEffects.append("throws")
            }
            if functionType.effectSpecifiers?.asyncSpecifier != nil, !coversAsync {
                uncoveredEffects.append("async")
            }
            guard !uncoveredEffects.isEmpty else {
                return nil
            }
            return Finding(
                .unsupportedAutoclosureEffect(
                    parameter: (parameter.secondName ?? parameter.firstName).text,
                    uncoveredEffects: uncoveredEffects,
                    inSubscript: inSubscript
                ),
                at: parameter
            )
        }
    }

    /// A requirement whose return type mentions a generic parameter inside a function
    /// type, such as `func makeSetter<T>() -> (T) -> Void`. The mock stores an erased
    /// handler and casts its result back to the declared return type, and the Swift
    /// runtime cannot convert between function types, so no cast can produce the
    /// closure the requirement promises.
    static func genericFunctionTypeReturn(_ requirement: Requirement) -> [Finding] {
        let returnType: TypeSyntax
        let genericParamNames: Set<String>
        let name: String
        switch requirement {
        case .function(let functionDecl):
            guard let type = functionDecl.signature.returnClause?.type else {
                return []
            }
            returnType = type
            genericParamNames = MockGenerator.extractGenericParameterNames(from: functionDecl)
            name = functionDecl.name.text
        case .subscript(let subscriptDecl):
            returnType = subscriptDecl.returnClause.type
            genericParamNames = MockGenerator.extractGenericParameterNames(from: subscriptDecl)
            name = "subscript"
        case .initializer, .variable, .associatedType, .typeAlias, .unsupported:
            return []
        }

        guard MockGenerator.typeContainsGeneric(returnType, genericParamNames: genericParamNames),
              !MockGenerator.erasedResultCanBeCast(to: returnType, genericParamNames: genericParamNames) else {
            return []
        }
        return [Finding(
            .unsupportedGenericReturn(requirement: name, returnType: returnType.trimmedDescription),
            at: requirement.decl
        )]
    }

    /// A closure parameter whose own parameters mention a generic parameter, such as
    /// `func observe<T>(_ handler: (T) -> Void)`. The mock forwards the argument to a
    /// handler that erases generic parameters, and a closure's parameters are
    /// contravariant, so `(T) -> Void` cannot be passed where `(Any) -> Void` is
    /// expected.
    static func genericClosureParameters(_ requirement: Requirement) -> [Finding] {
        let parameters: FunctionParameterListSyntax
        let genericParamNames: Set<String>
        let name: String
        switch requirement {
        case .function(let functionDecl):
            parameters = functionDecl.signature.parameterClause.parameters
            genericParamNames = MockGenerator.extractGenericParameterNames(from: functionDecl)
            name = functionDecl.name.text
        case .initializer(let initDecl):
            parameters = initDecl.signature.parameterClause.parameters
            genericParamNames = MockGenerator.extractGenericParameterNames(from: initDecl)
            name = "init"
        case .subscript(let subscriptDecl):
            parameters = subscriptDecl.parameterClause.parameters
            genericParamNames = MockGenerator.extractGenericParameterNames(from: subscriptDecl)
            name = "subscript"
        case .variable, .associatedType, .typeAlias, .unsupported:
            return []
        }

        return parameters.compactMap { parameter in
            guard !MockGenerator.erasedArgumentCanBeForwarded(for: parameter.type, genericParamNames: genericParamNames) else {
                return nil
            }
            return Finding(
                .unsupportedGenericParameter(
                    requirement: name,
                    parameter: (parameter.secondName ?? parameter.firstName).text,
                    parameterType: parameter.type.trimmedDescription
                ),
                at: parameter
            )
        }
    }

    /// An `associatedtype` the mock cannot satisfy. The mock fulfills an associated
    /// type with a `typealias`, using the requirement's default when it has one and
    /// `Any` otherwise. `Any` satisfies an unconstrained requirement, but not one
    /// carrying a conformance or a `where` clause, and the resulting error would name
    /// the mock rather than the requirement it cannot meet.
    static func constrainedAssociatedType(_ requirement: Requirement) -> [Finding] {
        guard case .associatedType(let associatedType) = requirement,
              associatedType.initializer == nil,
              associatedType.inheritanceClause != nil || associatedType.genericWhereClause != nil else {
            return []
        }
        return [Finding(.unsupportedAssociatedType(name: associatedType.name.text), at: associatedType)]
    }
}
