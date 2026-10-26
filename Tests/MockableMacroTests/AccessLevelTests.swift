import SwiftSyntax
import Testing

@testable import MockableMacros

@Suite("AccessLevel Tests")
struct AccessLevelTests {
    private func accessLevel(ofProtocol source: String) -> AccessLevel? {
        let decl: DeclSyntax = "\(raw: source)"
        guard let protocolDecl = decl.as(ProtocolDeclSyntax.self) else {
            return nil
        }
        return AccessLevel.from(protocolDecl: protocolDecl)
    }

    // MARK: - from(protocolDecl:)

    @Test(
        "from(protocolDecl:) reads the explicit access modifier",
        arguments: [
            ("public protocol Service {}", AccessLevel.public),
            ("package protocol Service {}", AccessLevel.package),
            ("internal protocol Service {}", AccessLevel.internal),
            ("fileprivate protocol Service {}", AccessLevel.fileprivate),
            ("private protocol Service {}", AccessLevel.private),
        ]
    )
    func explicitAccessModifier(source: String, expected: AccessLevel) {
        #expect(accessLevel(ofProtocol: source) == expected)
    }

    @Test("from(protocolDecl:) defaults to internal without an explicit modifier")
    func defaultAccessLevel() {
        #expect(accessLevel(ofProtocol: "protocol Service {}") == .internal)
    }

    @Test("from(protocolDecl:) ignores non-access modifiers")
    func nonAccessModifiersIgnored() {
        #expect(accessLevel(ofProtocol: "public protocol Service: Sendable {}") == .public)
    }

    // MARK: - modifier(for:)

    @Test("internal needs no modifier in any role")
    func internalHasNoModifier() {
        for role in [AccessLevel.DeclarationRole.mockType, .subclassableMockType, .member, .overridableMember] {
            #expect(AccessLevel.internal.modifier(for: role) == nil)
        }
    }

    @Test("A public mock type is open only where it may be subclassed")
    func publicMockType() {
        #expect(AccessLevel.public.modifier(for: .mockType)?.name.text == "public")
        #expect(AccessLevel.public.modifier(for: .subclassableMockType)?.name.text == "open")
    }

    @Test("A private mock type stays private")
    func privateMockType() {
        #expect(AccessLevel.private.modifier(for: .mockType)?.name.text == "private")
        #expect(AccessLevel.private.modifier(for: .subclassableMockType)?.name.text == "private")
    }

    @Test("Members of a private protocol are fileprivate")
    func privateMembersAreFileprivate() {
        #expect(AccessLevel.private.modifier(for: .member)?.name.text == "fileprivate")
        #expect(AccessLevel.private.modifier(for: .overridableMember)?.name.text == "fileprivate")
        #expect(AccessLevel.fileprivate.modifier(for: .member)?.name.text == "fileprivate")
    }

    @Test("A public member is open only where it may be overridden")
    func publicMember() {
        #expect(AccessLevel.public.modifier(for: .member)?.name.text == "public")
        #expect(AccessLevel.public.modifier(for: .overridableMember)?.name.text == "open")
    }

    @Test("A package member is never open")
    func packageMembersStayPackage() {
        #expect(AccessLevel.package.modifier(for: .member)?.name.text == "package")
        #expect(AccessLevel.package.modifier(for: .overridableMember)?.name.text == "package")
    }
}
