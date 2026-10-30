import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Variable Mock Generation

extension MockGenerator {
    /// Generates the members that mock a property requirement. A plain stored property is
    /// settable on the mock whatever the requirement allows, so a test sets it up as
    /// `mock.name = value`: it is either its own stored property (an optional one on the
    /// direct path) or a computed property over a private `_name` slot. An effectful
    /// read-only requirement (`get async`/`throws`) is handler-based like a method (see
    /// `generateEffectfulGetterMock`). Handles one `VariableDeclSyntax`, which may
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
                if let effectfulGetter = AccessorInspection.effectfulGetter(of: binding) {
                    members.append(contentsOf: generateEffectfulGetterMock(
                        requirement: requirement,
                        getter: effectfulGetter
                    ))
                }

            case .storedVariable(let varType, let isOptional, _):
                let field = requirement.trackingFields(model: access.model)[0]

                // An optional property on the direct path is its own storage, and
                // satisfies the requirement on its own.
                if field.name == requirement.identifier {
                    members.append(contentsOf: trackingMemberItems(for: requirement))
                    continue
                }

                // Otherwise the slot is private to the mock — on the direct path a
                // stored `_name`, on the lock-backed path a field of the storage
                // struct — and the settable witness is the only way to reach it.
                if case .direct = access {
                    members.append(MemberBlockItemSyntax(decl: Self.makeStoredProperty(
                        modifiers: DeclModifierListSyntax([DeclModifierSyntax(name: .keyword(.private))] + scope.modifiers),
                        name: field.name,
                        type: field.type,
                        initializer: field.initialValue
                    )))
                }

                members.append(MemberBlockItemSyntax(decl: generateVariableWitness(
                    varName: requirement.identifier,
                    varType: varType,
                    isOptional: isOptional,
                    scope: scope,
                    leavesMockIsolation: requirement.leavesMockIsolation,
                    access: access
                )))

            default:
                continue
            }
        }

        return members
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
            handlerType: requirement.handlerType ?? TrackingRequirement.fallbackHandlerType,
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
            handlerCallArguments: "",
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

    /// The property witness of a stored property: reads and writes its private
    /// `_name` slot the way `access` prescribes. It is settable even for a get-only
    /// requirement, which a get-set property satisfies, so a test sets it up as
    /// `mock.name = value` and the slot needs no public spelling. A non-optional
    /// requirement force-unwraps the optional slot, so reading before the test sets a
    /// value traps rather than silently returning a placeholder.
    ///
    /// On lock-backed access the witness is `nonisolated` wherever the slot it reads
    /// has to be reachable from outside the mock's isolation (see
    /// `storageBackedMemberModifiers`): a test then sets up an actor mock's property
    /// without hopping to the actor, as it already sets its handlers.
    private func generateVariableWitness(
        varName: String,
        varType: TypeSyntax,
        isOptional: Bool,
        scope: MemberScope,
        leavesMockIsolation: Bool,
        access: TrackingAccess
    ) -> VariableDeclSyntax {
        let backingName = MockNaming.variableBacking(varName)
        var additionalModifiers = scope.modifiers
        if case .lockBacked = access {
            additionalModifiers.append(contentsOf: storageBackedMemberModifiers(
                leavesMockIsolation: leavesMockIsolation,
                scope: scope
            ))
        }
        let modifiers = modifiers(for: .member, additional: additionalModifiers)
        let getterBody = access.read(isOptional ? backingName : "\(backingName)!")

        return Self.makeGetSetProperty(
            modifiers: modifiers,
            name: varName,
            type: varType.trimmed,
            getterBody: getterBody,
            setterBody: access.write(backingName, "newValue")
        )
    }
}
