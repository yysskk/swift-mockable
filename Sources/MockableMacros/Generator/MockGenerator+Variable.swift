import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Variable Mock Generation

extension MockGenerator {
    /// Generates the members that mock a property requirement. A plain stored property is
    /// backed by a settable `_name` (or the property itself, for optional get-set), while an
    /// effectful read-only requirement (`get async`/`throws`) is handler-based like a method
    /// (see `generateEffectfulGetterMock`). Handles one `VariableDeclSyntax`, which may
    /// declare several bindings; `scope` and `leavesMockIsolation` are the
    /// declaration's, read from its `Requirement`.
    func generateVariableMock(
        _ varDecl: VariableDeclSyntax,
        scope: MemberScope,
        leavesMockIsolation: Bool
    ) -> [MemberBlockItemSyntax] {
        var members: [MemberBlockItemSyntax] = []
        let access = trackingAccess(for: scope)

        for binding in varDecl.bindings {
            guard let requirement = variableTrackingRequirement(
                for: binding,
                scope: scope,
                leavesMockIsolation: leavesMockIsolation
            ) else {
                continue
            }

            switch requirement.kind {
            // Effectful read-only properties (`get async`/`get throws`) are mocked with
            // a handler and a call counter instead of backing storage: a stored value
            // cannot model a thrown error, and the handler mirrors the function model.
            case .effectfulVariable:
                if let effectfulGetter = Self.effectfulGetter(of: binding) {
                    members.append(contentsOf: generateEffectfulGetterMock(
                        requirement: requirement,
                        getter: effectfulGetter
                    ))
                }

            case .storedVariable(let varType, let isOptional, let isGetOnly):
                // The backing slot: a settable `_name`, or — for an optional get-set
                // property on the direct path — the property itself, which then
                // satisfies the requirement on its own.
                members.append(contentsOf: trackingMemberItems(for: requirement))
                let isSelfBacked = requirement.trackingFields(model: access.model)
                    .contains { $0.name == requirement.identifier }
                if isSelfBacked {
                    continue
                }

                members.append(MemberBlockItemSyntax(decl: generateVariableWitness(
                    varName: requirement.identifier,
                    varType: varType,
                    isOptional: isOptional,
                    isGetOnly: isGetOnly,
                    scope: scope,
                    access: access
                )))

            default:
                continue
            }
        }

        return members
    }

    /// A property binding with no accessor block is not treated as get-only,
    /// hence the `false` default.
    static func isGetOnlyProperty(binding: PatternBindingSyntax) -> Bool {
        isGetOnly(binding.accessorBlock, defaultWhenAbsent: false)
    }

    /// Returns the `get` accessor of a binding when it carries `async`/`throws`
    /// effects (e.g. `var token: String { get async throws }`), or `nil` otherwise.
    static func effectfulGetter(of binding: PatternBindingSyntax) -> AccessorDeclSyntax? {
        effectfulGetAccessor(in: binding.accessorBlock)
    }

    /// The handler closure type for an effectful read-only property, e.g.
    /// `() async throws -> String`.
    static func effectfulGetterClosureType(
        varType: TypeSyntax,
        effects: AccessorEffectSpecifiersSyntax?
    ) -> String {
        "()\(effectsSuffix(for: effects)) -> \(varType.trimmedDescription)"
    }

    /// Generates the members that mock an effectful read-only property: the tracking
    /// slots plus a witness whose getter keeps the requirement's `async`/`throws`
    /// effects, records the call, and forwards to the handler.
    private func generateEffectfulGetterMock(
        requirement: TrackingRequirement,
        getter: AccessorDeclSyntax
    ) -> [MemberBlockItemSyntax] {
        guard case .effectfulVariable(let varType) = requirement.kind else {
            return []
        }

        let varName = requirement.identifier
        let scope = requirement.scope
        let effects = getter.effectSpecifiers
        let isAsync = effects?.asyncSpecifier != nil
        let isThrows = effects?.hasThrowsEffect ?? false
        var members = trackingMemberItems(for: requirement)

        let invokePrefix = "\(isThrows ? "try " : "")\(isAsync ? "await " : "")"
        let elseBody = Self.unsetHandlerElseBody(returnType: varType, handlerName: MockNaming.handler(varName))
        let errorType = effects?.throwsErrorType?.trimmedDescription

        // A property getter takes no parameters, so nothing can shadow the locals the
        // body binds and they keep their default names. The call is counted but has no
        // arguments to record.
        let names = WitnessNames(parameters: FunctionParameterListSyntax([]))
        let binding = trackingAccess(for: scope).handlerBinding(
            identifier: varName,
            recordedArguments: nil,
            handlerType: requirement.handlerType ?? TrackingRequirement.handlerType(forClosure: "() -> Void"),
            names: names
        )

        var getterStatements = binding.statements
        getterStatements.append(Self.makeUnsetHandlerGuard(
            binding: binding.pattern,
            elseBody: elseBody,
            leadingTrivia: .newline
        ))
        getterStatements.append(Self.makeHandlerReturnStatement(
            invokePrefix: invokePrefix,
            handlerName: names.handler,
            handlerCallArgs: "",
            errorType: errorType,
            leadingTrivia: .newline
        ))

        // The protocol witness stays actor-isolated on actor mocks (like every other
        // generated witness); only the auxiliary CallCount/Handler storage members are
        // `nonisolated`, which they already get via `generateTrackingStorageProperty`.
        let property = VariableDeclSyntax(
            modifiers: modifiers(for: .member, additional: scope.modifiers),
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier(varName)),
                    typeAnnotation: TypeAnnotationSyntax(type: varType.trimmed),
                    accessorBlock: AccessorBlockSyntax(
                        accessors: .accessors(AccessorDeclListSyntax([
                            AccessorDeclSyntax(
                                accessorSpecifier: .keyword(.get),
                                effectSpecifiers: getter.effectSpecifiers?.trimmed,
                                body: CodeBlockSyntax(
                                    leftBrace: .leftBraceToken(trailingTrivia: .newline),
                                    statements: CodeBlockItemListSyntax(getterStatements),
                                    rightBrace: .rightBraceToken(leadingTrivia: .newline)
                                )
                            )
                        ]))
                    )
                )
            ])
        )
        members.append(MemberBlockItemSyntax(decl: property))

        return members
    }

    /// The property witness of a stored property: reads its `_name` backing slot the
    /// way `access` prescribes, and writes it for a get-set requirement. A non-optional
    /// requirement force-unwraps the optional slot, so reading before the test sets a
    /// value traps rather than silently returning a placeholder.
    private func generateVariableWitness(
        varName: String,
        varType: TypeSyntax,
        isOptional: Bool,
        isGetOnly: Bool,
        scope: MemberScope,
        access: TrackingAccess
    ) -> VariableDeclSyntax {
        let backingName = MockNaming.variableBacking(varName)
        let modifiers = modifiers(for: .member, additional: scope.modifiers)
        let getterBody = access.read(isOptional ? backingName : "\(backingName)!")

        if isGetOnly {
            return Self.makeGetOnlyProperty(
                modifiers: modifiers,
                name: varName,
                type: varType.trimmed,
                getterBody: getterBody
            )
        }

        return Self.makeGetSetProperty(
            modifiers: modifiers,
            name: varName,
            type: varType.trimmed,
            getterBody: getterBody,
            setterBody: access.write(backingName, "newValue")
        )
    }
}
