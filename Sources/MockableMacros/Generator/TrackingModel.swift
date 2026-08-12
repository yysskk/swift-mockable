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
/// `resetValue` back to it.
struct TrackingField {
    /// What the slot stores.
    enum Role {
        case callCount
        case callArgs
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
    /// The initial value expression (`0`, `[]`, `nil`).
    let initialValue: ExprSyntax
    /// The right-hand side of the `resetMock()` assignment (`"0"`, `"[]"`, `"nil"`).
    let resetValue: String
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
        /// unwrapped optionals; an optional get-set property on the direct path is
        /// its own storage (no `_name` backing).
        case storedVariable(varType: TypeSyntax, isOptional: Bool, isGetOnly: Bool)
        /// A `get async`/`get throws` property: handler-based, no backing storage.
        case effectfulVariable(varType: TypeSyntax)
        case subscriptRequirement(isGetOnly: Bool)
    }

    /// The disambiguated base identifier, e.g. `fetchUser`, `fetchUserIntString`,
    /// `subscriptInt`, `init`, `theme`.
    let identifier: String
    let isTypeMember: Bool
    let kind: Kind
    /// The tuple element type of the `CallArgs` array; `nil` for properties.
    let callArgsTupleType: TypeSyntax?
    /// The handler closure type, e.g. `(Int) async throws -> String`; `nil` for
    /// initializers and stored properties.
    let handlerClosureType: String?
    /// The setter-handler closure type of a get-set subscript.
    let setHandlerClosureType: String?

    /// The requirement's stored tracking slots, in emission order. This order is
    /// the single source of truth: every consumer emits fields exactly as listed.
    func trackingFields(model: StorageModel) -> [TrackingField] {
        switch kind {
        case .function:
            return [callCountField, callArgsField, handlerField]
        case .initializer:
            return [callCountField, callArgsField]
        case .effectfulVariable:
            return [callCountField, handlerField]
        case .subscriptRequirement(let isGetOnly):
            var fields = [callCountField, callArgsField, handlerField]
            if !isGetOnly {
                fields.append(setHandlerField)
            }
            return fields
        case .storedVariable(let varType, let isOptional, let isGetOnly):
            return [backingField(model: model, varType: varType, isOptional: isOptional, isGetOnly: isGetOnly)]
        }
    }

    private var callCountField: TrackingField {
        TrackingField(
            role: .callCount,
            name: MockNaming.callCount(identifier),
            type: TypeSyntax(stringLiteral: "Int"),
            initialValue: ExprSyntax(IntegerLiteralExprSyntax(literal: .integerLiteral("0"))),
            resetValue: "0"
        )
    }

    private var callArgsField: TrackingField {
        TrackingField(
            role: .callArgs,
            name: MockNaming.callArgs(identifier),
            type: TypeSyntax(ArrayTypeSyntax(element: callArgsTupleType ?? TypeSyntax(stringLiteral: "Void"))),
            initialValue: ExprSyntax(ArrayExprSyntax(elements: ArrayElementListSyntax([]))),
            resetValue: "[]"
        )
    }

    private var handlerField: TrackingField {
        TrackingField(
            role: .handler,
            name: MockNaming.handler(identifier),
            type: TypeSyntax(stringLiteral: "(@Sendable \(handlerClosureType ?? "() -> Void"))?"),
            initialValue: ExprSyntax(NilLiteralExprSyntax()),
            resetValue: "nil"
        )
    }

    private var setHandlerField: TrackingField {
        TrackingField(
            role: .setHandler,
            name: MockNaming.setHandler(identifier),
            type: TypeSyntax(stringLiteral: "(@Sendable \(setHandlerClosureType ?? "() -> Void"))?"),
            initialValue: ExprSyntax(NilLiteralExprSyntax()),
            resetValue: "nil"
        )
    }

    private func backingField(
        model: StorageModel,
        varType: TypeSyntax,
        isOptional: Bool,
        isGetOnly: Bool
    ) -> TrackingField {
        // An optional get-set property on the direct path is its own storage: the
        // mock declares `var theme: Theme? = nil` and resets the property itself.
        let isSelfBacked = model == .direct && isOptional && !isGetOnly
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
            initialValue: ExprSyntax(NilLiteralExprSyntax()),
            resetValue: "nil"
        )
    }
}

/// The overload information shared by every requirement of one protocol, computed
/// once per `generate()` pass instead of re-walking the member tree per consumer.
struct OverloadContext {
    let methodGroups: [String: [FunctionDeclSyntax]]
    let initializers: [InitializerDeclSyntax]
    let subscripts: [SubscriptDeclSyntax]
}

extension MockGenerator {
    func makeOverloadContext() -> OverloadContext {
        let decls = collectDeclsIncludingConditional()
        return OverloadContext(
            methodGroups: groupMethodsByNameIncludingConditional(),
            initializers: decls.compactMap { $0.as(InitializerDeclSyntax.self) },
            subscripts: decls.compactMap { $0.as(SubscriptDeclSyntax.self) }
        )
    }

    /// The tracking requirements declared by one member declaration: one per
    /// function, initializer, or subscript, and one per property binding.
    ///
    /// Must be handed the original declaration nodes from `members` — overload
    /// ordinals compare node identity, so a re-parsed copy would break the
    /// `...2` suffixes.
    func trackingRequirements(for decl: DeclSyntax, overloads: OverloadContext) -> [TrackingRequirement] {
        if let initDecl = decl.as(InitializerDeclSyntax.self) {
            return [initializerTrackingRequirement(for: initDecl, overloads: overloads)]
        }

        if let funcDecl = decl.as(FunctionDeclSyntax.self) {
            return [functionTrackingRequirement(for: funcDecl, overloads: overloads)]
        }

        if let varDecl = decl.as(VariableDeclSyntax.self) {
            let isTypeMember = Self.isTypeMember(varDecl.modifiers)
            return varDecl.bindings.compactMap { binding in
                variableTrackingRequirement(for: binding, isTypeMember: isTypeMember)
            }
        }

        if let subscriptDecl = decl.as(SubscriptDeclSyntax.self) {
            return [subscriptTrackingRequirement(for: subscriptDecl, overloads: overloads)]
        }

        return []
    }

    func initializerTrackingRequirement(
        for initDecl: InitializerDeclSyntax,
        overloads: OverloadContext
    ) -> TrackingRequirement {
        let genericParamNames = Self.extractGenericParameterNames(from: initDecl)
        return TrackingRequirement(
            identifier: Self.initializerIdentifier(for: initDecl, in: overloads.initializers),
            isTypeMember: false,
            kind: .initializer,
            callArgsTupleType: Self.buildCallArgsTupleType(
                parameters: initDecl.signature.parameterClause.parameters,
                genericParamNames: genericParamNames
            ),
            handlerClosureType: nil,
            setHandlerClosureType: nil
        )
    }

    func functionTrackingRequirement(
        for funcDecl: FunctionDeclSyntax,
        overloads: OverloadContext
    ) -> TrackingRequirement {
        let funcName = funcDecl.name.text
        let methodGroup = overloads.methodGroups[funcName] ?? []
        let suffix = methodGroup.count > 1 ? Self.functionIdentifierSuffix(from: funcDecl, in: methodGroup) : ""
        let parameters = funcDecl.signature.parameterClause.parameters
        let isAsync = funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil
        // `rethrows` requirements get a non-throwing handler (see MockGenerator+Function).
        let handlerThrows = (funcDecl.signature.effectSpecifiers?.hasThrowsEffect ?? false)
            && (funcDecl.signature.effectSpecifiers?.isRethrows != true)
        let genericParamNames = Self.extractGenericParameterNames(from: funcDecl)
        return TrackingRequirement(
            identifier: suffix.isEmpty ? funcName : "\(funcName)\(suffix)",
            isTypeMember: Self.isTypeMember(funcDecl.modifiers),
            kind: .function,
            callArgsTupleType: Self.buildCallArgsTupleType(parameters: parameters, genericParamNames: genericParamNames),
            handlerClosureType: buildFunctionClosureType(
                parameters: parameters,
                returnType: funcDecl.signature.returnClause?.type,
                isAsync: isAsync,
                isThrows: handlerThrows,
                genericParamNames: genericParamNames
            ),
            setHandlerClosureType: nil
        )
    }

    /// The tracking requirement of one property binding, or `nil` for a binding
    /// without a name or type annotation (which cannot be mocked).
    func variableTrackingRequirement(
        for binding: PatternBindingSyntax,
        isTypeMember: Bool
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
                isTypeMember: isTypeMember,
                kind: .effectfulVariable(varType: varType),
                callArgsTupleType: nil,
                handlerClosureType: Self.effectfulGetterClosureType(
                    varType: varType,
                    effects: effectfulGetter.effectSpecifiers
                ),
                setHandlerClosureType: nil
            )
        }

        let isOptional = varType.is(OptionalTypeSyntax.self) || varType.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)
        return TrackingRequirement(
            identifier: varName,
            isTypeMember: isTypeMember,
            kind: .storedVariable(
                varType: varType,
                isOptional: isOptional,
                isGetOnly: Self.isGetOnlyProperty(binding: binding)
            ),
            callArgsTupleType: nil,
            handlerClosureType: nil,
            setHandlerClosureType: nil
        )
    }

    func subscriptTrackingRequirement(
        for subscriptDecl: SubscriptDeclSyntax,
        overloads: OverloadContext
    ) -> TrackingRequirement {
        let parameters = subscriptDecl.parameterClause.parameters
        let returnType = subscriptDecl.returnClause.type
        let genericParamNames = Self.extractGenericParameterNames(from: subscriptDecl)
        let isGetOnly = Self.isGetOnlySubscript(subscriptDecl)
        let suffix = Self.subscriptIdentifierSuffix(from: subscriptDecl, in: overloads.subscripts)
        return TrackingRequirement(
            identifier: MockNaming.subscriptIdentifier(suffix: suffix),
            isTypeMember: false,
            kind: .subscriptRequirement(isGetOnly: isGetOnly),
            callArgsTupleType: Self.buildCallArgsTupleType(parameters: parameters, genericParamNames: genericParamNames),
            handlerClosureType: buildSubscriptGetterClosureType(
                parameters: parameters,
                returnType: returnType,
                genericParamNames: genericParamNames,
                effects: Self.effectfulSubscriptGetter(subscriptDecl)?.effectSpecifiers
            ),
            setHandlerClosureType: isGetOnly ? nil : buildSubscriptSetterClosureType(
                parameters: parameters,
                returnType: returnType,
                genericParamNames: genericParamNames
            )
        )
    }
}
