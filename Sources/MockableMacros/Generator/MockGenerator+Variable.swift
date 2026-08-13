import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Variable Mock Generation

extension MockGenerator {
    /// Generates the members that mock a property requirement. A plain stored property is
    /// backed by a settable `_name` (or the property itself, for optional get-set), while an
    /// effectful read-only requirement (`get async`/`throws`) is handler-based like a method
    /// (see `generateEffectfulGetterMock`). Handles one `VariableDeclSyntax`, which may
    /// declare several bindings.
    func generateVariableMock(
        _ varDecl: VariableDeclSyntax
    ) -> [MemberBlockItemSyntax] {
        var members: [MemberBlockItemSyntax] = []
        let isTypeMember = Self.isTypeMember(varDecl.modifiers)
        let shouldUseLockBasedStorage = usesLockBasedStorage(isTypeMember: isTypeMember)

        for binding in varDecl.bindings {
            guard let requirement = variableTrackingRequirement(for: binding, isTypeMember: isTypeMember) else {
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
                if shouldUseLockBasedStorage {
                    let field = requirement.trackingFields(model: .lockBacked)[0]
                    members.append(MemberBlockItemSyntax(decl: generateLockBackedBackingProperty(
                        field: field,
                        isTypeMember: isTypeMember
                    )))
                    members.append(MemberBlockItemSyntax(decl: generateLockBasedVariableProperty(
                        varName: requirement.identifier,
                        varType: varType,
                        isGetOnly: isGetOnly,
                        isTypeMember: isTypeMember
                    )))
                    continue
                }

                let field = requirement.trackingFields(model: .direct)[0]
                members.append(MemberBlockItemSyntax(decl: Self.makeStoredProperty(
                    modifiers: buildModifiers(additional: Self.typeMemberModifiers(isTypeMember: isTypeMember)),
                    name: field.name,
                    type: field.type,
                    initializer: field.initialValue
                )))

                if isGetOnly {
                    members.append(MemberBlockItemSyntax(decl: generateComputedGetProperty(
                        varName: requirement.identifier,
                        varType: varType,
                        isTypeMember: isTypeMember
                    )))
                } else if !isOptional {
                    members.append(MemberBlockItemSyntax(decl: generateComputedGetSetProperty(
                        varName: requirement.identifier,
                        varType: varType,
                        isTypeMember: isTypeMember
                    )))
                }
                // An optional get-set property is its own storage: the stored
                // property above already satisfies the requirement.

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
        let isTypeMember = requirement.isTypeMember
        let effects = getter.effectSpecifiers
        let isAsync = effects?.asyncSpecifier != nil
        let isThrows = effects?.hasThrowsEffect ?? false
        let closureType = requirement.handlerClosureType ?? "() -> Void"
        let shouldUseLockBasedStorage = usesLockBasedStorage(isTypeMember: isTypeMember)

        var members = trackingMemberItems(for: requirement)

        let invokePrefix = "\(isThrows ? "try " : "")\(isAsync ? "await " : "")"
        let elseBody = Self.unsetHandlerElseBody(returnType: varType, handlerName: MockNaming.handler(varName))
        let errorType = effects?.throwsErrorType?.trimmedDescription

        var getterStatements: [CodeBlockItemSyntax] = []
        if shouldUseLockBasedStorage {
            let storageName = Self.storagePropertyName(isTypeMember: isTypeMember)
            getterStatements.append(CodeBlockItemSyntax(item: .decl(DeclSyntax(stringLiteral: """
let _handler = \(storageName).withLock { storage -> (@Sendable \(closureType))? in
    storage.\(MockNaming.callCount(varName)) += 1
    return storage.\(MockNaming.handler(varName))
}
"""))))
            getterStatements.append(Self.makeUnsetHandlerGuard(
                binding: "_handler",
                elseBody: elseBody,
                leadingTrivia: .newline
            ))
        } else {
            getterStatements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: "\(MockNaming.callCount(varName)) += 1"))))
            getterStatements.append(Self.makeUnsetHandlerGuard(
                binding: "_handler = \(MockNaming.handler(varName))",
                elseBody: elseBody,
                leadingTrivia: .newline
            ))
        }
        // A property getter takes no parameters, so nothing can shadow the local the
        // handler is bound to and it keeps the default name.
        getterStatements.append(Self.makeHandlerReturnStatement(
            invokePrefix: invokePrefix,
            handlerName: "_handler",
            handlerCallArgs: "",
            errorType: errorType,
            leadingTrivia: .newline
        ))

        // The protocol witness stays actor-isolated on actor mocks (like every other
        // generated witness); only the auxiliary CallCount/Handler storage members are
        // `nonisolated`, which they already get via `generateTrackingStorageProperty`.
        let property = VariableDeclSyntax(
            modifiers: buildModifiers(additional: Self.typeMemberModifiers(isTypeMember: isTypeMember)),
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

    /// The public write-through accessor of a lock-backed `_name` slot: reads and
    /// writes the storage-struct field of the same name inside the lock.
    private func generateLockBackedBackingProperty(
        field: TrackingField,
        isTypeMember: Bool
    ) -> VariableDeclSyntax {
        var additionalModifiers = Self.typeMemberModifiers(isTypeMember: isTypeMember)
        if !isTypeMember {
            additionalModifiers.append(contentsOf: storageBackedMemberModifiers())
        }

        return Self.makeLockBackedProperty(
            modifiers: buildModifiers(additional: additionalModifiers),
            name: field.name,
            type: field.type,
            storageName: Self.storagePropertyName(isTypeMember: isTypeMember),
            storedName: field.name
        )
    }

    /// The property witness of a lock-backed stored property, reading (and, for a
    /// get-set requirement, writing) its `_name` slot through the lock. A non-optional
    /// requirement force-unwraps the optional slot, so reading before the test sets a
    /// value traps rather than silently returning a placeholder.
    private func generateLockBasedVariableProperty(
        varName: String,
        varType: TypeSyntax,
        isGetOnly: Bool,
        isTypeMember: Bool
    ) -> VariableDeclSyntax {
        let isOptional = varType.is(OptionalTypeSyntax.self) || varType.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)
        let storageName = Self.storagePropertyName(isTypeMember: isTypeMember)
        let additionalModifiers = Self.typeMemberModifiers(isTypeMember: isTypeMember)

        let getterBody: String
        if isOptional {
            getterBody = "\(storageName).withLock { $0.\(MockNaming.variableBacking(varName)) }"
        } else {
            getterBody = "\(storageName).withLock { $0.\(MockNaming.variableBacking(varName))! }"
        }

        if isGetOnly {
            return Self.makeGetOnlyProperty(
                modifiers: buildModifiers(additional: additionalModifiers),
                name: varName,
                type: varType.trimmed,
                getterBody: getterBody
            )
        }

        return Self.makeGetSetProperty(
            modifiers: buildModifiers(additional: additionalModifiers),
            name: varName,
            type: varType.trimmed,
            getterBody: getterBody,
            setterBody: "\(storageName).withLock { $0.\(MockNaming.variableBacking(varName)) = newValue }"
        )
    }

    /// The get-only witness of a stored property, reading its `_name` backing storage
    /// (force-unwrapped for a non-optional requirement).
    private func generateComputedGetProperty(
        varName: String,
        varType: TypeSyntax,
        isTypeMember: Bool
    ) -> VariableDeclSyntax {
        let isOptional = varType.is(OptionalTypeSyntax.self) ||
                         varType.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)

        let getterBody: String
        if isOptional {
            getterBody = "\(MockNaming.variableBacking(varName))"
        } else {
            getterBody = "\(MockNaming.variableBacking(varName))!"
        }

        return Self.makeGetOnlyProperty(
            modifiers: buildModifiers(additional: Self.typeMemberModifiers(isTypeMember: isTypeMember)),
            name: varName,
            type: varType.trimmed,
            getterBody: getterBody
        )
    }

    /// The get-set witness of a non-optional stored property, reading and writing
    /// its `_name` backing storage.
    private func generateComputedGetSetProperty(
        varName: String,
        varType: TypeSyntax,
        isTypeMember: Bool
    ) -> VariableDeclSyntax {
        Self.makeGetSetProperty(
            modifiers: buildModifiers(additional: Self.typeMemberModifiers(isTypeMember: isTypeMember)),
            name: varName,
            type: varType.trimmed,
            getterBody: "\(MockNaming.variableBacking(varName))!",
            setterBody: "\(MockNaming.variableBacking(varName)) = newValue"
        )
    }
}
