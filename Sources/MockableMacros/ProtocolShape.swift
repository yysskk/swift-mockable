import SwiftSyntax

/// The protocol-level facts that drive mock generation, read once from the
/// declaration's name, attributes, inheritance clause, and modifiers.
///
/// `Sendable`/`Actor` conformances select the lock-backed storage model, an
/// inherited protocol produces a subclassing mock, and the access level decides
/// the generated modifiers.
struct ProtocolShape {
    /// The protocol's declared name.
    let protocolName: String
    /// Whether the protocol requires `Sendable` conformance, by inheriting
    /// `Sendable` or being marked `@Sendable`.
    let isSendable: Bool
    /// Whether the protocol inherits `Actor`, producing an actor mock.
    let isActor: Bool
    /// The global actor the protocol is isolated to, as spelled in its attribute
    /// (`MainActor`, `DataActor`, `Module.DataActor`), or `nil` for a protocol that
    /// declares no isolation of its own.
    let globalActorName: String?
    /// Inherited types that name parent protocols, in declaration order.
    let parentProtocolNames: [String]
    /// Inherited types the generated mock cannot be made to conform to, reported
    /// as diagnostics instead of expanding to code that does not compile.
    let unsupportedInheritedTypes: [UnsupportedInheritedType]
    /// The protocol's declared access level (`internal` when unspecified).
    let accessLevel: AccessLevel

    /// The name of the generated mock type, e.g. `UserService` -> `UserServiceMock`.
    var mockClassName: String {
        MockNaming.mockTypeName(forProtocol: protocolName)
    }

    /// The mock superclass name derived from the first parent protocol, or `nil`
    /// for a protocol without parents.
    var parentMockClassName: String? {
        parentProtocolNames.first.map { MockNaming.mockTypeName(forProtocol: $0) }
    }

    /// Whether the generated mock subclasses a parent protocol's mock, inheriting its
    /// members and initializers. An actor mock is final and cannot subclass, so an
    /// actor protocol re-implements its parent's requirements instead.
    var subclassesParentMock: Bool {
        parentMockClassName != nil && !isActor
    }

    /// Whether the protocol is isolated to a global actor, so the mock's members are too.
    var isGlobalActorIsolated: Bool {
        globalActorName != nil
    }

    /// Whether the generated type can be subclassed from another module, which decides
    /// whether `public` members are emitted as `open`. Actor mocks are always final.
    var canBeSubclassedOutsideModule: Bool {
        accessLevel == .public && !isActor
    }

    init(_ protocolDecl: ProtocolDeclSyntax) {
        let inheritedTypes = protocolDecl.inheritanceClause?.inheritedTypes ?? []
        var parentProtocolNames: [String] = []
        var unsupportedInheritedTypes: [UnsupportedInheritedType] = []

        for inherited in inheritedTypes {
            switch InheritedTypeKind(inherited.type) {
            case .marker, .external:
                continue
            case .parent(let name):
                parentProtocolNames.append(name)
            case .unsupported(let name, let reason):
                unsupportedInheritedTypes.append(
                    UnsupportedInheritedType(type: inherited, name: name, reason: reason)
                )
            }
        }

        self.protocolName = protocolDecl.name.text
        // `Error` refines `Sendable`, so a protocol inheriting it requires the same
        // storage model and the same `@unchecked Sendable` conformance.
        self.isSendable = protocolDecl.inherits("Sendable")
            || protocolDecl.inherits("Error")
            || protocolDecl.hasAttribute(named: "Sendable")
        self.isActor = protocolDecl.inherits("Actor")
        self.globalActorName = protocolDecl.globalActorAttributeName()
        self.parentProtocolNames = parentProtocolNames
        self.unsupportedInheritedTypes = unsupportedInheritedTypes
        self.accessLevel = AccessLevel.from(protocolDecl: protocolDecl)
    }
}

/// An inherited type the generated mock cannot be made to conform to.
struct UnsupportedInheritedType {
    /// Why the mock cannot conform to it.
    enum Reason {
        /// A protocol with requirements the mock has no way to witness, and no
        /// generated mock of its own to inherit them from.
        case requirementsCannotBeWitnessed
        /// A parent protocol written with generic arguments, which the mock cannot
        /// name a superclass for.
        case parameterized
    }

    /// The node the diagnostic is attached to.
    let type: InheritedTypeSyntax
    /// The inherited type as written.
    let name: String
    /// Why the mock cannot conform to it; `MockableDiagnostic` words the explanation.
    let reason: Reason
}

/// How an inherited type is treated when building the mock.
private enum InheritedTypeKind {
    /// A protocol the mock satisfies simply by declaring the conformance, because it
    /// has no requirements to witness.
    case marker
    /// A protocol whose own `@Mockable` mock the generated mock subclasses.
    case parent(String)
    /// A protocol named with a qualifier other than `Swift.`, usually one declared in
    /// another module. The mock only declares the conformance: the requirements it has
    /// to witness are the ones the annotated protocol restates in its own body.
    case external
    /// A protocol the mock cannot be made to conform to.
    case unsupported(String, UnsupportedInheritedType.Reason)

    /// Protocols that declare no requirement a witness has to provide, so a mock
    /// conforms to them for free. `Actor` and `Sendable` also select the mock's
    /// storage model; see `ProtocolShape`.
    private static let markers: Set<String> = [
        "Sendable", "Actor", "AnyObject", "AnyActor", "Error",
        "Copyable", "Escapable", "BitwiseCopyable",
    ]

    /// Standard-library protocols with requirements the macro cannot witness. They
    /// have no generated mock either, so treating them as parent protocols would
    /// produce a mock inheriting from a type that does not exist.
    private static let unwitnessable: Set<String> = [
        "Equatable", "Hashable", "Comparable", "Identifiable",
        "Codable", "Encodable", "Decodable",
        "CustomStringConvertible", "CustomDebugStringConvertible", "LosslessStringConvertible",
        "CaseIterable", "RawRepresentable",
        "Sequence", "AsyncSequence", "Collection", "IteratorProtocol",
    ]

    init(_ type: TypeSyntax) {
        // A parameterized conformance (`Container<Int>`) names no type the mock can
        // subclass, and a mock for it could not be found by name either. A qualified
        // spelling (`SomeModule.Container<Int>`) is the same thing written differently.
        if Self.isParameterized(type) {
            self = .unsupported(type.trimmedDescription, .parameterized)
            return
        }

        let name = Self.unqualifiedName(of: type)
        if Self.markers.contains(name) {
            self = .marker
        } else if Self.unwitnessable.contains(name) {
            self = .unsupported(type.trimmedDescription, .requirementsCannotBeWitnessed)
        } else if type.is(MemberTypeSyntax.self) && !Self.isSwiftQualified(type) {
            // `Shared.UserRepository` names a protocol whose mock, if there is one at
            // all, is not `Shared.UserRepositoryMock`. This is how a protocol restates
            // an imported one so that `@Mockable` can see its requirements.
            self = .external
        } else {
            self = .parent(name)
        }
    }

    /// Whether the type is qualified with the `Swift` module, as in `Swift.Sendable`.
    private static func isSwiftQualified(_ type: TypeSyntax) -> Bool {
        type.trimmedDescription.hasPrefix("Swift.")
    }

    /// Whether the type is written with generic arguments, in either the plain
    /// (`Container<Int>`) or the qualified (`SomeModule.Container<Int>`) spelling.
    private static func isParameterized(_ type: TypeSyntax) -> Bool {
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return identifier.genericArgumentClause != nil
        }
        if let member = type.as(MemberTypeSyntax.self) {
            return member.genericArgumentClause != nil
        }
        return false
    }

    /// The inherited type's name with a `Swift.` module qualifier removed, so
    /// `Swift.Sendable` is recognized as the marker it is. Only that qualifier is
    /// stripped: any other one names a type the macro knows nothing about.
    private static func unqualifiedName(of type: TypeSyntax) -> String {
        let name = type.trimmedDescription
        guard name.hasPrefix("Swift.") else {
            return name
        }
        return String(name.dropFirst("Swift.".count))
    }
}

private extension ProtocolDeclSyntax {
    /// Whether the inheritance clause names the given type, e.g. `protocol P: Sendable`,
    /// including the `Swift.`-qualified spelling.
    func inherits(_ name: String) -> Bool {
        inheritanceClause?.inheritedTypes.contains { inherited in
            let inheritedName = inherited.type.trimmedDescription
            return inheritedName == name || inheritedName == "Swift.\(name)"
        } ?? false
    }

    /// The name of the attribute isolating the protocol to a global actor, if any. A
    /// global actor attribute names a type (`@MainActor`, `@DataActor`, possibly
    /// module-qualified) and takes no arguments, and the only other type-named
    /// attributes a protocol carries are `@Sendable` and attached macros such as
    /// `@Mockable` itself; any other capitalized attribute is taken for a global actor.
    /// The `(unsafe)` argument of a pre-Swift 6 `@MainActor(unsafe)` is accepted too.
    func globalActorAttributeName() -> String? {
        attributes.lazy
            .compactMap { attribute -> AttributeSyntax? in
                // An attribute inside `#if` is not read: the mock's own attribute
                // would have to be conditional too.
                if case .attribute(let attributeSyntax) = attribute {
                    return attributeSyntax
                }
                return nil
            }
            .first { attributeSyntax in
                let baseName: String
                if let memberType = attributeSyntax.attributeName.as(MemberTypeSyntax.self) {
                    baseName = memberType.name.text
                } else if let identifierType = attributeSyntax.attributeName.as(IdentifierTypeSyntax.self) {
                    baseName = identifierType.name.text
                } else {
                    return false
                }
                guard let first = baseName.first, first.isUppercase else {
                    return false
                }
                if baseName == "Sendable" || baseName == "Mockable" {
                    return false
                }
                if let arguments = attributeSyntax.arguments, arguments.trimmedDescription != "unsafe" {
                    return false
                }
                return true
            }
            .map { $0.attributeName.trimmedDescription }
    }

    /// Whether the protocol carries the given attribute, e.g. `@MainActor protocol P`.
    func hasAttribute(named name: String) -> Bool {
        attributes.contains { attribute in
            if case .attribute(let attributeSyntax) = attribute {
                return attributeSyntax.attributeName.trimmedDescription == name
            }
            return false
        }
    }
}
