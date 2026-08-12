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

    // MARK: - makeModifier(supportsOpen:)

    @Test("makeModifier returns nil for internal")
    func internalHasNoModifier() {
        #expect(AccessLevel.internal.makeModifier() == nil)
        #expect(AccessLevel.internal.makeModifier(supportsOpen: true) == nil)
    }

    @Test("makeModifier keeps public when open is unsupported")
    func publicStaysPublic() {
        #expect(AccessLevel.public.makeModifier()?.name.text == "public")
    }

    @Test("makeModifier promotes public to open when open is supported")
    func publicBecomesOpen() {
        #expect(AccessLevel.public.makeModifier(supportsOpen: true)?.name.text == "open")
    }

    @Test("makeModifier keeps private as private for the type declaration")
    func privateTypeModifier() {
        #expect(AccessLevel.private.makeModifier()?.name.text == "private")
        #expect(AccessLevel.private.makeModifier(supportsOpen: true)?.name.text == "private")
    }

    // MARK: - makeMemberModifier(isOverridable:)

    @Test("makeMemberModifier returns nil for internal")
    func internalHasNoMemberModifier() {
        #expect(AccessLevel.internal.makeMemberModifier() == nil)
    }

    @Test("makeMemberModifier maps private members to fileprivate")
    func privateMembersAreFileprivate() {
        #expect(AccessLevel.private.makeMemberModifier()?.name.text == "fileprivate")
    }

    @Test("makeMemberModifier keeps fileprivate members fileprivate")
    func fileprivateMembersStayFileprivate() {
        #expect(AccessLevel.fileprivate.makeMemberModifier()?.name.text == "fileprivate")
    }

    @Test("makeMemberModifier promotes public members to open only when overridable")
    func publicMemberPromotion() {
        #expect(AccessLevel.public.makeMemberModifier()?.name.text == "public")
        #expect(AccessLevel.public.makeMemberModifier(isOverridable: true)?.name.text == "open")
    }

    @Test("makeMemberModifier never promotes package members to open")
    func packageMembersStayPackage() {
        #expect(AccessLevel.package.makeMemberModifier(isOverridable: true)?.name.text == "package")
    }
}
