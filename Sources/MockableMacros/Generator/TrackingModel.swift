import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Tracking Model

/// Which storage flavor a consumer emits tracking state for.
///
/// The same requirement produces differently named and typed slots depending on
/// where they live: `.direct` describes plain stored properties on the mock
/// itself, `.lockBacked` the fields inside the `Storage`/`StaticStorage` structs
/// guarded by `MockableLock`.
enum StorageModel {
    case direct
    case lockBacked
}

/// One stored tracking slot generated for a requirement, e.g. `fetchCallCount`.
///
/// A field knows everything its consumers need: the storage-struct generator
/// emits `var name: Type = initialValue`, the mock-member generator emits the
/// same slot as a stored or lock-backed property, and `resetMock()` assigns
/// `initialValue` back to it.
struct TrackingField {
    /// What the slot stores.
    enum Role {
        case callCount
        case callArguments
        case handler
        case setHandler
        /// The `_name` backing storage of a stored property (or the property
        /// itself, for an optional get-set property on the direct path).
        case backing
    }

    let role: Role
    /// The member name, e.g. `fetchCallCount`, `_theme`, `subscriptIntSetHandler`.
    let name: String
    /// The exact emitted type.
    let type: TypeSyntax
    /// The initial value expression (`0`, `[]`, `nil`), which `resetMock()` assigns
    /// back to the slot.
    let initialValue: ExprSyntax
}

/// The tracking identity and shape of one protocol requirement, computed once and
/// shared by every consumer, so the storage struct, the public tracking members,
/// and `resetMock()` can never disagree about a requirement's slots.
struct TrackingRequirement {
    enum Kind {
        case function
        /// Initializers record calls but have no handler.
        case initializer
        /// A property backed by stored state. `isOptional` includes implicitly
        /// unwrapped optionals; an optional property on the direct path is its own
        /// storage (no `_name` backing).
        case storedVariable(varType: TypeSyntax, isOptional: Bool, isGetOnly: Bool)
        /// A `get async`/`get throws` property: handler-based, no backing storage.
        case effectfulVariable(varType: TypeSyntax)
        case subscriptRequirement(isGetOnly: Bool)
    }

    /// The disambiguated base identifier, e.g. `fetchUser`, `fetchUserIntString`,
    /// `subscriptInt`, `init`, `theme`.
    let identifier: String
    /// Whether the requirement is instance or type state.
    let scope: MemberScope
    /// Whether the requirement's witness takes an isolation other than the mock's —
    /// it is declared `nonisolated`, or has an `isolated` parameter — so the tracking
    /// members that witness reaches have to be nonisolated.
    var leavesMockIsolation: Bool = false
    let kind: Kind
    /// The tuple element type of the `CallArguments` array; `nil` for properties.
    let callArgumentsTupleType: TypeSyntax?
    /// The type of the `<name>Handler` slot, an optional `@Sendable` closure such as
    /// `(@Sendable (Int) async throws -> String)?`; `nil` for initializers and
    /// stored properties, which have no handler.
    let handlerType: TypeSyntax?
    /// The type of the `<name>SetHandler` slot of a get-set subscript.
    let setHandlerType: TypeSyntax?

    /// The handler slot's type for a closure type: the closure made `@Sendable`, so a
    /// test can install it on a mock shared across tasks, and optional, since it is
    /// unset until the test installs one.
    static func handlerType(forClosure closureType: String) -> TypeSyntax {
        TypeSyntax(stringLiteral: "(@Sendable \(closureType))?")
    }

    /// The requirement's stored tracking slots, in emission order. This order is
    /// the single source of truth: every consumer emits fields exactly as listed.
    func trackingFields(model: StorageModel) -> [TrackingField] {
        switch kind {
        case .function:
            return [callCountField, callArgumentsField, handlerField]
        case .initializer:
            return [callCountField, callArgumentsField]
        case .effectfulVariable:
            return [callCountField, handlerField]
        case .subscriptRequirement(let isGetOnly):
            var fields = [callCountField, callArgumentsField, handlerField]
            if !isGetOnly {
                fields.append(setHandlerField)
            }
            return fields
        case .storedVariable(let varType, let isOptional, _):
            return [backingField(model: model, varType: varType, isOptional: isOptional)]
        }
    }

    /// The `<name>CallCount` slot.
    private var callCountField: TrackingField {
        TrackingField(
            role: .callCount,
            name: MockNaming.callCount(identifier),
            type: TypeSyntax(stringLiteral: "Int"),
            initialValue: ExprSyntax(IntegerLiteralExprSyntax(literal: .integerLiteral("0")))
        )
    }

    /// The `<name>CallArguments` slot, an array of the requirement's argument tuple.
    private var callArgumentsField: TrackingField {
        TrackingField(
            role: .callArguments,
            name: MockNaming.callArguments(identifier),
            type: TypeSyntax(ArrayTypeSyntax(element: callArgumentsTupleType ?? TypeSyntax(stringLiteral: "Void"))),
            initialValue: ExprSyntax(ArrayExprSyntax(elements: ArrayElementListSyntax([])))
        )
    }

    /// The `<name>Handler` slot, an optional `@Sendable` closure.
    private var handlerField: TrackingField {
        TrackingField(
            role: .handler,
            name: MockNaming.handler(identifier),
            type: handlerType ?? Self.handlerType(forClosure: "() -> Void"),
            initialValue: ExprSyntax(NilLiteralExprSyntax())
        )
    }

    /// The `<name>SetHandler` slot of a get-set subscript.
    private var setHandlerField: TrackingField {
        TrackingField(
            role: .setHandler,
            name: MockNaming.setHandler(identifier),
            type: setHandlerType ?? Self.handlerType(forClosure: "() -> Void"),
            initialValue: ExprSyntax(NilLiteralExprSyntax())
        )
    }

    /// The stored slot behind a property requirement. It is always optional so an
    /// unset non-optional property traps on read rather than needing a placeholder,
    /// and it is named `_name` except for an optional property on the direct path,
    /// where the property itself is the storage.
    private func backingField(
        model: StorageModel,
        varType: TypeSyntax,
        isOptional: Bool
    ) -> TrackingField {
        // An optional property on the direct path is its own storage: the mock
        // declares `var theme: Theme? = nil`, which satisfies a get-only requirement
        // as well as a get-set one, and resets the property itself.
        let isSelfBacked = model == .direct && isOptional
        let storageType: TypeSyntax
        if isOptional {
            storageType = varType.trimmed
        } else {
            storageType = TypeSyntax(OptionalTypeSyntax(wrappedType: varType.trimmed))
        }
        return TrackingField(
            role: .backing,
            name: isSelfBacked ? identifier : MockNaming.variableBacking(identifier),
            type: storageType,
            initialValue: ExprSyntax(NilLiteralExprSyntax())
        )
    }
}

/// The overload information shared by every requirement of one protocol, computed
/// once per `generate()` pass instead of re-walking the member tree per consumer.
struct OverloadContext {
    /// The protocol's method requirements grouped by name, so an overloaded method
    /// can be told apart from a sole one.
    let methodGroups: [String: [FunctionDeclSyntax]]
    let initializers: [InitializerDeclSyntax]
    let subscripts: [SubscriptDeclSyntax]
    /// The identifier each requirement's tracking members are named after, assigned
    /// across the whole protocol so no two requirements share one. Keyed by the
    /// declaration's node identity, so lookups need the original nodes.
    let trackingIdentifiers: [SyntaxIdentifier: String]

    /// The identifier assigned to a requirement, falling back to what the requirement
    /// suggests on its own. The fallback covers a declaration the assignment pass did
    /// not see, which can only happen if a caller builds a requirement from a node
    /// outside the protocol's member block.
    func trackingIdentifier(for id: SyntaxIdentifier, suggestion: @autoclosure () -> String) -> String {
        trackingIdentifiers[id] ?? suggestion()
    }
}

extension OverloadContext {
    /// Groups the protocol's requirements once — methods by name, and every
    /// initializer and subscript — and assigns their tracking identifiers, so each
    /// consumer can disambiguate without re-walking the member tree.
    init(requirements: [Requirement]) {
        var methodGroups: [String: [FunctionDeclSyntax]] = [:]
        var initializers: [InitializerDeclSyntax] = []
        var subscripts: [SubscriptDeclSyntax] = []
        for requirement in requirements {
            switch requirement {
            case .function(let funcDecl):
                methodGroups[funcDecl.name.text, default: []].append(funcDecl)
            case .initializer(let initDecl):
                initializers.append(initDecl)
            case .subscript(let subscriptDecl):
                subscripts.append(subscriptDecl)
            case .variable, .associatedType, .typeAlias, .unsupported:
                continue
            }
        }
        self.init(
            methodGroups: methodGroups,
            initializers: initializers,
            subscripts: subscripts,
            trackingIdentifiers: MockGenerator.assignTrackingIdentifiers(
                in: requirements,
                methodGroups: methodGroups,
                initializers: initializers,
                subscripts: subscripts
            )
        )
    }
}

extension MockGenerator {

    /// The tracking requirements declared by one protocol requirement: one per
    /// function, initializer, or subscript, one per property binding, and none for a
    /// type declaration.
    ///
    /// Must be handed a requirement built from the original declaration nodes in
    /// `members` — overload ordinals compare node identity, so a re-parsed copy would
    /// break the `...2` suffixes.
    func trackingRequirements(for requirement: Requirement, overloads: OverloadContext) -> [TrackingRequirement] {
        switch requirement {
        case .initializer(let initDecl):
            return [initializerTrackingRequirement(for: initDecl, overloads: overloads)]

        case .function(let funcDecl):
            return [functionTrackingRequirement(
                for: funcDecl,
                scope: requirement.scope,
                leavesMockIsolation: requirement.leavesMockIsolation,
                overloads: overloads
            )]

        case .variable(let varDecl):
            return varDecl.bindings.compactMap { binding in
                variableTrackingRequirement(
                    for: binding,
                    scope: requirement.scope,
                    leavesMockIsolation: requirement.leavesMockIsolation
                )
            }

        case .subscript(let subscriptDecl):
            return [subscriptTrackingRequirement(
                for: subscriptDecl,
                leavesMockIsolation: requirement.leavesMockIsolation,
                overloads: overloads
            )]

        case .associatedType, .typeAlias, .unsupported:
            return []
        }
    }

    /// The tracking requirement of an `init` requirement. Initializers record calls but
    /// have no handler, and are never type members.
    func initializerTrackingRequirement(
        for initDecl: InitializerDeclSyntax,
        overloads: OverloadContext
    ) -> TrackingRequirement {
        let genericParamNames = Self.extractGenericParameterNames(from: initDecl)
        return TrackingRequirement(
            identifier: overloads.trackingIdentifier(
                for: initDecl.id,
                suggestion: Self.suggestedIdentifier(for: initDecl, in: overloads.initializers)
            ),
            scope: .instance,
            kind: .initializer,
            callArgumentsTupleType: Self.buildCallArgumentsTupleType(
                parameters: initDecl.signature.parameterClause.parameters,
                genericParamNames: genericParamNames
            ),
            handlerType: nil,
            setHandlerType: nil
        )
    }

    /// The tracking requirement of a method, with its identifier disambiguated against
    /// the protocol's other methods of the same name. `scope` and
    /// `leavesMockIsolation` are the declaration's, read from its `Requirement`.
    func functionTrackingRequirement(
        for funcDecl: FunctionDeclSyntax,
        scope: MemberScope,
        leavesMockIsolation: Bool,
        overloads: OverloadContext
    ) -> TrackingRequirement {
        let funcName = funcDecl.name.text
        let methodGroup = overloads.methodGroups[funcName] ?? []
        let parameters = funcDecl.signature.parameterClause.parameters
        let isAsync = funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil
        // `rethrows` requirements get a non-throwing handler (see MockGenerator+Function).
        let handlerThrows = (funcDecl.signature.effectSpecifiers?.hasThrowsEffect ?? false)
            && (funcDecl.signature.effectSpecifiers?.isRethrows != true)
        let genericParamNames = Self.extractGenericParameterNames(from: funcDecl)
        return TrackingRequirement(
            identifier: overloads.trackingIdentifier(
                for: funcDecl.id,
                suggestion: Self.suggestedIdentifier(for: funcDecl, in: methodGroup)
            ),
            scope: scope,
            leavesMockIsolation: leavesMockIsolation,
            kind: .function,
            callArgumentsTupleType: Self.buildCallArgumentsTupleType(parameters: parameters, genericParamNames: genericParamNames),
            handlerType: TrackingRequirement.handlerType(forClosure: buildFunctionClosureType(
                parameters: parameters,
                returnType: funcDecl.signature.returnClause?.type,
                isAsync: isAsync,
                isThrows: handlerThrows,
                genericParamNames: genericParamNames
            )),
            setHandlerType: nil
        )
    }

    /// The tracking requirement of one property binding, or `nil` for a binding
    /// without a name or type annotation (which cannot be mocked).
    func variableTrackingRequirement(
        for binding: PatternBindingSyntax,
        scope: MemberScope,
        leavesMockIsolation: Bool
    ) -> TrackingRequirement? {
        guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
              let typeAnnotation = binding.typeAnnotation else {
            return nil
        }

        let varName = identifier.identifier.text
        let varType = typeAnnotation.type

        if let effectfulGetter = Self.effectfulGetter(of: binding) {
            return TrackingRequirement(
                identifier: varName,
                scope: scope,
                leavesMockIsolation: leavesMockIsolation,
                kind: .effectfulVariable(varType: varType),
                callArgumentsTupleType: nil,
                handlerType: TrackingRequirement.handlerType(forClosure: Self.effectfulGetterClosureType(
                    varType: varType,
                    effects: effectfulGetter.effectSpecifiers
                )),
                setHandlerType: nil
            )
        }

        let isOptional = varType.is(OptionalTypeSyntax.self) || varType.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)
        return TrackingRequirement(
            identifier: varName,
            scope: scope,
            leavesMockIsolation: leavesMockIsolation,
            kind: .storedVariable(
                varType: varType,
                isOptional: isOptional,
                isGetOnly: Self.isGetOnlyProperty(binding: binding)
            ),
            callArgumentsTupleType: nil,
            handlerType: nil,
            setHandlerType: nil
        )
    }

    /// The tracking requirement of a subscript. Generated members cannot be named after
    /// a subscript's (absent) base name, so the identifier always carries a type suffix,
    /// disambiguated against the protocol's other subscripts. `leavesMockIsolation` is
    /// the declaration's, read from its `Requirement`.
    func subscriptTrackingRequirement(
        for subscriptDecl: SubscriptDeclSyntax,
        leavesMockIsolation: Bool,
        overloads: OverloadContext
    ) -> TrackingRequirement {
        let parameters = subscriptDecl.parameterClause.parameters
        let returnType = subscriptDecl.returnClause.type
        let genericParamNames = Self.extractGenericParameterNames(from: subscriptDecl)
        let isGetOnly = Self.isGetOnlySubscript(subscriptDecl)
        return TrackingRequirement(
            identifier: overloads.trackingIdentifier(
                for: subscriptDecl.id,
                suggestion: Self.suggestedIdentifier(for: subscriptDecl, in: overloads.subscripts)
            ),
            scope: .instance,
            leavesMockIsolation: leavesMockIsolation,
            kind: .subscriptRequirement(isGetOnly: isGetOnly),
            callArgumentsTupleType: Self.buildCallArgumentsTupleType(parameters: parameters, genericParamNames: genericParamNames),
            handlerType: TrackingRequirement.handlerType(forClosure: buildSubscriptGetterClosureType(
                parameters: parameters,
                returnType: returnType,
                genericParamNames: genericParamNames,
                effects: Self.effectfulSubscriptGetter(subscriptDecl)?.effectSpecifiers
            )),
            setHandlerType: isGetOnly ? nil : TrackingRequirement.handlerType(forClosure: buildSubscriptSetterClosureType(
                parameters: parameters,
                returnType: returnType,
                genericParamNames: genericParamNames
            ))
        )
    }
}
