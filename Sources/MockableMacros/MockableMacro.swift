import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// The implementation of the `@Mockable` attached peer macro.
///
/// Applied to a protocol, it generates a `<Protocol>Mock` class (wrapped in `#if DEBUG`
/// by default; the `condition:` argument selects a different guard, see
/// ``CompilationCondition``) that conforms to the protocol and records calls, captures
/// arguments, and exposes a configurable handler for every requirement. The protocol's
/// shape drives the output: `Sendable`/`Actor` conformances select a lock-backed storage
/// model, an inherited protocol produces a subclassing mock, and unsupported members are
/// reported as diagnostics (see ``MockableError``) instead of generating invalid code.
public struct MockableMacro: PeerMacro {
    /// Generates the mock class peer for a `@Mockable` protocol.
    ///
    /// Returns an empty array (emitting diagnostics) when the declaration is not a
    /// protocol, when the macro's arguments are invalid, or when a member cannot be
    /// mocked.
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let protocolDecl = declaration.as(ProtocolDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: Syntax(node), message: MockableError.notAProtocol))
            return []
        }

        // The protocol-level shape drives both diagnostics and code generation.
        let shape = ProtocolShape(protocolDecl)

        // `nil` means the arguments were invalid and diagnostics were emitted; the
        // member diagnostics below still run so all problems surface in one pass.
        let condition = CompilationCondition.parse(from: node, in: context)
        let hasUnsupportedMembers = diagnoseUnsupportedMembers(in: protocolDecl.memberBlock.members, context: context)
        let hasUnsupportedInheritance = diagnoseInheritedTypes(shape.unsupportedInheritedTypes, context: context)
        // An `init` declared directly on a protocol whose mock subclasses another is not yet
        // mockable: the witness would need to chain through the parent mock's initializer,
        // which the macro cannot see. Initializers inherited from the parent still work, since
        // the child mock inherits the parent mock's `required init`.
        let hasUnsupportedInitializers = diagnoseInitializerContext(
            in: protocolDecl.memberBlock.members,
            isUnsupportedContext: shape.subclassesParentMock,
            context: context
        )
        guard let condition, !hasUnsupportedMembers, !hasUnsupportedInheritance, !hasUnsupportedInitializers else {
            return []
        }

        // Diagnostics above read the protocol as written; generation reads it with every
        // requirement's parameters renamed to something the generated bodies can refer
        // to (see `ParameterNameNormalizer`). Normalizing once, here, keeps every later
        // pass looking at the same nodes.
        let members = ParameterNameNormalizer().visit(protocolDecl.memberBlock.members)

        let mockClass = MockGenerator(shape: shape, members: members).generate()

        return [condition.wrapping(mockClass)]
    }

    /// Reports an `associatedtype` the mock cannot satisfy, returning whether it did.
    ///
    /// The mock fulfills an associated type with a `typealias`, using the requirement's
    /// default when it has one and `Any` otherwise. `Any` satisfies an unconstrained
    /// requirement, but not one carrying a conformance or a `where` clause, and the
    /// resulting error names the mock rather than the requirement it cannot meet.
    private static func diagnoseConstrainedAssociatedType(
        _ associatedType: AssociatedTypeDeclSyntax,
        context: some MacroExpansionContext
    ) -> Bool {
        guard associatedType.initializer == nil,
              associatedType.inheritanceClause != nil || associatedType.genericWhereClause != nil else {
            return false
        }

        let name = associatedType.name.text
        context.diagnose(Diagnostic(
            node: Syntax(associatedType),
            message: MockableError.unsupportedAssociatedType("""
                Cannot mock associated type '\(name)': the mock fulfills it with 'Any', \
                which does not satisfy its constraints. Give it a default \
                ('associatedtype \(name): ... = SomeType') so the mock has a type to use.
                """)
        ))
        return true
    }

    /// Reports every inherited type the generated mock cannot be made to conform to,
    /// returning whether any was found. Without this the mock would be emitted with a
    /// conformance it does not satisfy, or a superclass that does not exist, and the
    /// error would point into the expansion rather than at the inheritance clause.
    private static func diagnoseInheritedTypes(
        _ unsupported: [UnsupportedInheritedType],
        context: some MacroExpansionContext
    ) -> Bool {
        for inherited in unsupported {
            context.diagnose(Diagnostic(
                node: Syntax(inherited.type),
                message: MockableError.unsupportedInheritedType(inherited.message)
            ))
        }
        return !unsupported.isEmpty
    }

    /// Reports every member the macro cannot mock, returning whether any was found.
    /// All members are visited, in every conditional-compilation clause, so one
    /// expansion surfaces every problem rather than making the author fix them one
    /// build at a time.
    private static func diagnoseUnsupportedMembers(
        in members: MemberBlockItemListSyntax,
        context: some MacroExpansionContext
    ) -> Bool {
        var hasError = false

        for requirement in Requirement.all(in: members) {
            if diagnoseUnsupportedRequirement(requirement, context: context) {
                hasError = true
            }
        }

        return hasError
    }

    /// Reports everything that prevents one requirement from being mocked, returning
    /// whether anything was found. The checks of a kind stop at the first finding, so a
    /// requirement is reported once.
    private static func diagnoseUnsupportedRequirement(
        _ requirement: Requirement,
        context: some MacroExpansionContext
    ) -> Bool {
        switch requirement {
        case .function(let functionDecl):
            if diagnoseUnsupportedName(functionDecl.name, of: Syntax(functionDecl), context: context) {
                return true
            }

            // Generated mock members evaluate @autoclosure arguments to record them,
            // so an autoclosure's own effects must be covered by the requirement.
            let effects = functionDecl.signature.effectSpecifiers
            if diagnoseAutoclosureParameters(
                functionDecl.signature.parameterClause.parameters,
                coversThrows: effects?.hasThrowsEffect ?? false,
                coversAsync: effects?.asyncSpecifier != nil,
                inSubscript: false,
                context: context
            ) {
                return true
            }
            let genericParamNames = MockGenerator.extractGenericParameterNames(from: functionDecl)
            if diagnoseGenericFunctionReturn(
                returnType: functionDecl.signature.returnClause?.type,
                genericParamNames: genericParamNames,
                node: Syntax(functionDecl),
                name: functionDecl.name.text,
                context: context
            ) {
                return true
            }
            return diagnoseGenericClosureParameters(
                functionDecl.signature.parameterClause.parameters,
                genericParamNames: genericParamNames,
                name: functionDecl.name.text,
                context: context
            )

        case .subscript(let subscriptDecl):
            // A static subscript has no storage to track.
            guard !requirement.isTypeMember else {
                diagnoseUnsupportedMember(subscriptDecl, context: context)
                return true
            }
            if diagnoseAutoclosureParameters(
                subscriptDecl.parameterClause.parameters,
                coversThrows: false,
                coversAsync: false,
                inSubscript: true,
                context: context
            ) {
                return true
            }
            let genericParamNames = MockGenerator.extractGenericParameterNames(from: subscriptDecl)
            if diagnoseGenericFunctionReturn(
                returnType: subscriptDecl.returnClause.type,
                genericParamNames: genericParamNames,
                node: Syntax(subscriptDecl),
                name: "subscript",
                context: context
            ) {
                return true
            }
            return diagnoseGenericClosureParameters(
                subscriptDecl.parameterClause.parameters,
                genericParamNames: genericParamNames,
                name: "subscript",
                context: context
            )

        case .initializer(let initDecl):
            // Initializer witnesses evaluate @autoclosure arguments to record them, so an
            // autoclosure's own effects must be covered by the requirement, as for methods.
            let effects = initDecl.signature.effectSpecifiers
            if diagnoseAutoclosureParameters(
                initDecl.signature.parameterClause.parameters,
                coversThrows: effects?.hasThrowsEffect ?? false,
                coversAsync: effects?.asyncSpecifier != nil,
                inSubscript: false,
                context: context
            ) {
                return true
            }
            return diagnoseGenericClosureParameters(
                initDecl.signature.parameterClause.parameters,
                genericParamNames: MockGenerator.extractGenericParameterNames(from: initDecl),
                name: "init",
                context: context
            )

        case .associatedType(let associatedType):
            return diagnoseConstrainedAssociatedType(associatedType, context: context)

        case .variable(let variableDecl):
            return diagnoseVariableNames(variableDecl, context: context)

        case .typeAlias:
            return false

        // A nested type, an operator declaration, or any other member kind the macro
        // cannot mock is reported rather than silently dropped from the mock.
        case .unsupported(let decl):
            diagnoseUnsupportedMember(decl, context: context)
            return true
        }
    }

    /// Reports a member kind the macro cannot mock at all.
    private static func diagnoseUnsupportedMember(
        _ decl: some DeclSyntaxProtocol,
        context: some MacroExpansionContext
    ) {
        context.diagnose(
            Diagnostic(node: Syntax(decl), message: MockableError.unsupportedMember(decl.trimmedDescription))
        )
    }

    /// Diagnoses a requirement whose name cannot be mocked. Generated members are named
    /// after the requirement — a method's tracking members append a suffix (`fetch` becomes
    /// `fetchCallCount`) and a property's backing storage takes a prefix (`name` becomes
    /// `_name`) — so a name that is not a plain identifier, such as an operator or a name
    /// written with backticks, would only produce illegal identifiers.
    private static func diagnoseUnsupportedName(
        _ name: TokenSyntax,
        of node: Syntax,
        context: some MacroExpansionContext
    ) -> Bool {
        let reason: String
        switch name.tokenKind {
        case .identifier(let text) where !text.contains("`"):
            return false
        case .binaryOperator, .prefixOperator, .postfixOperator:
            reason = "operator requirements are not supported"
        default:
            reason = "only requirements whose name is a plain identifier can be mocked"
        }

        context.diagnose(
            Diagnostic(
                node: node,
                message: MockableError.unsupportedMemberName("Cannot mock '\(name.text)': \(reason)")
            )
        )
        return true
    }

    /// Diagnoses the property requirements declared by one `var`, which may bind several
    /// names. Bindings the generator skips (those without a plain identifier pattern) are
    /// skipped here too, so the check covers exactly the names it would generate from.
    private static func diagnoseVariableNames(
        _ variableDecl: VariableDeclSyntax,
        context: some MacroExpansionContext
    ) -> Bool {
        var hasError = false

        for binding in variableDecl.bindings {
            guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier else {
                continue
            }
            if diagnoseUnsupportedName(identifier, of: Syntax(variableDecl), context: context) {
                hasError = true
            }
        }

        return hasError
    }

    /// Diagnoses `@autoclosure` parameters whose own effects (`throws`/`async`)
    /// are not covered by the enclosing requirement. The generated mock evaluates
    /// autoclosure arguments once per call to record them, which is only possible
    /// when the surrounding member can apply `try`/`await`.
    private static func diagnoseAutoclosureParameters(
        _ parameters: FunctionParameterListSyntax,
        coversThrows: Bool,
        coversAsync: Bool,
        inSubscript: Bool,
        context: some MacroExpansionContext
    ) -> Bool {
        var hasError = false

        for param in parameters {
            guard let functionType = MockGenerator.autoclosureFunctionType(of: param) else {
                continue
            }
            let isThrowing = functionType.effectSpecifiers?.hasThrowsEffect ?? false
            let isAsync = functionType.effectSpecifiers?.asyncSpecifier != nil

            var uncoveredEffects: [String] = []
            if isThrowing && !coversThrows {
                uncoveredEffects.append("throws")
            }
            if isAsync && !coversAsync {
                uncoveredEffects.append("async")
            }
            guard !uncoveredEffects.isEmpty else {
                continue
            }

            let name = (param.secondName ?? param.firstName).text
            let message: String
            if inSubscript {
                message = "Cannot mock @autoclosure parameter '\(name)': effectful autoclosures are not supported in subscript requirements"
            } else {
                let effects = uncoveredEffects.joined(separator: "' and '")
                message = "Cannot mock @autoclosure parameter '\(name)': the mock evaluates autoclosure arguments when called, so the requirement must be declared '\(effects)'"
            }
            context.diagnose(
                Diagnostic(node: Syntax(param), message: MockableError.unsupportedAutoclosureEffect(message))
            )
            hasError = true
        }

        return hasError
    }

    /// Diagnoses a closure parameter whose own parameters mention a generic parameter, such
    /// as `func observe<T>(_ handler: (T) -> Void)`. The mock forwards the argument to a
    /// handler that erases generic parameters, and a closure's parameters are contravariant,
    /// so `(T) -> Void` cannot be passed where `(Any) -> Void` is expected.
    private static func diagnoseGenericClosureParameters(
        _ parameters: FunctionParameterListSyntax,
        genericParamNames: Set<String>,
        name: String,
        context: some MacroExpansionContext
    ) -> Bool {
        var hasError = false

        for parameter in parameters
        where !MockGenerator.erasedArgumentCanBeForwarded(
            for: parameter.type,
            genericParamNames: genericParamNames
        ) {
            let parameterName = (parameter.secondName ?? parameter.firstName).text
            context.diagnose(
                Diagnostic(
                    node: Syntax(parameter),
                    message: MockableError.unsupportedGenericParameter(
                        """
                        Cannot mock '\(name)': the parameter '\(parameterName)' is a closure whose own \
                        parameters mention a generic parameter. The mock forwards it to a handler that \
                        erases generic parameters, and a closure taking '\(parameter.type.trimmedDescription)' \
                        cannot be passed where one taking erased parameters is expected
                        """
                    )
                )
            )
            hasError = true
        }

        return hasError
    }

    /// Diagnoses a requirement whose return type mentions a generic parameter inside a
    /// function type, such as `func makeSetter<T>() -> (T) -> Void`. The mock stores an
    /// erased handler and casts its result back to the declared return type, and the Swift
    /// runtime cannot convert between function types, so no cast can produce the closure the
    /// requirement promises.
    private static func diagnoseGenericFunctionReturn(
        returnType: TypeSyntax?,
        genericParamNames: Set<String>,
        node: Syntax,
        name: String,
        context: some MacroExpansionContext
    ) -> Bool {
        guard let returnType,
              MockGenerator.typeContainsGeneric(returnType, genericParamNames: genericParamNames),
              !MockGenerator.erasedResultCanBeCast(to: returnType, genericParamNames: genericParamNames) else {
            return false
        }

        context.diagnose(
            Diagnostic(
                node: node,
                message: MockableError.unsupportedGenericReturn(
                    """
                    Cannot mock '\(name)': its return type '\(returnType.trimmedDescription)' mentions a \
                    generic parameter inside a function type. The mock erases generic parameters in its \
                    handler and casts the result back, and Swift cannot convert between function types \
                    at runtime
                    """
                )
            )
        )
        return true
    }

    /// Diagnoses `init` requirements that appear in a context the macro cannot yet mock.
    /// When `isUnsupportedContext` is `false` (a plain, non-inheriting protocol) no
    /// diagnostics are emitted and initializers are generated normally.
    private static func diagnoseInitializerContext(
        in members: MemberBlockItemListSyntax,
        isUnsupportedContext: Bool,
        context: some MacroExpansionContext
    ) -> Bool {
        guard isUnsupportedContext else {
            return false
        }

        var hasError = false

        for requirement in Requirement.all(in: members) {
            guard case .initializer(let initDecl) = requirement else {
                continue
            }
            context.diagnose(
                Diagnostic(
                    node: Syntax(initDecl),
                    message: MockableError.unsupportedInitializer(
                        "init requirements declared on an inheriting protocol are not yet supported"
                    )
                )
            )
            hasError = true
        }

        return hasError
    }
}
