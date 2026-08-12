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
    /// Whether the protocol is marked `@MainActor`.
    let isMainActor: Bool
    /// Inherited types that name parent protocols, excluding marker conformances
    /// that never correspond to a parent mock (`Sendable`, `Actor`, `AnyObject`,
    /// `AnyActor`).
    let parentProtocolNames: [String]
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

    init(_ protocolDecl: ProtocolDeclSyntax) {
        let knownNonParentProtocols: Set<String> = ["Sendable", "Actor", "AnyObject", "AnyActor"]

        self.protocolName = protocolDecl.name.text
        self.isSendable = protocolDecl.inherits("Sendable") || protocolDecl.hasAttribute(named: "Sendable")
        self.isActor = protocolDecl.inherits("Actor")
        self.isMainActor = protocolDecl.hasAttribute(named: "MainActor")
        self.parentProtocolNames = protocolDecl.inheritanceClause?.inheritedTypes
            .map { $0.type.trimmedDescription }
            .filter { !knownNonParentProtocols.contains($0) }
            ?? []
        self.accessLevel = AccessLevel.from(protocolDecl: protocolDecl)
    }
}

private extension ProtocolDeclSyntax {
    /// Whether the inheritance clause names the given type, e.g. `protocol P: Sendable`.
    func inherits(_ name: String) -> Bool {
        inheritanceClause?.inheritedTypes.contains { inherited in
            inherited.type.trimmedDescription == name
        } ?? false
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
