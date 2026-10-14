import SwiftSyntax
import Testing

@testable import MockableMacros

@Suite("Protocol Shape Tests")
struct ProtocolShapeTests {
    private func makeShape(of source: String) -> ProtocolShape? {
        let decl: DeclSyntax = "\(raw: source)"
        guard let protocolDecl = decl.as(ProtocolDeclSyntax.self) else {
            return nil
        }
        return ProtocolShape(protocolDecl)
    }

    @Test("A plain protocol has no conformance flags and internal access")
    func plainProtocol() throws {
        let shape = try #require(makeShape(of: "protocol Service {}"))
        #expect(shape.protocolName == "Service")
        #expect(shape.mockClassName == "ServiceMock")
        #expect(!shape.isSendable)
        #expect(!shape.isActor)
        #expect(shape.globalActorName == nil)
        #expect(shape.parentProtocolNames.isEmpty)
        #expect(shape.parentMockClassName == nil)
        #expect(shape.accessLevel == .internal)
    }

    @Test("Sendable is detected from inheritance and from the attribute")
    func sendableDetection() throws {
        let inherited = try #require(makeShape(of: "protocol Service: Sendable {}"))
        #expect(inherited.isSendable)

        let attributed = try #require(makeShape(of: "@Sendable protocol Service {}"))
        #expect(attributed.isSendable)
    }

    @Test("Actor and MainActor markers are detected")
    func actorDetection() throws {
        let actor = try #require(makeShape(of: "protocol Worker: Actor {}"))
        #expect(actor.isActor)
        #expect(actor.globalActorName == nil)

        let mainActor = try #require(makeShape(of: "@MainActor protocol ViewModel {}"))
        #expect(mainActor.globalActorName == "MainActor")
        #expect(!mainActor.isActor)
    }

    @Test("A custom global actor attribute is detected, qualified or not")
    func customGlobalActorDetection() throws {
        let custom = try #require(makeShape(of: "@DataActor protocol Store {}"))
        #expect(custom.globalActorName == "DataActor")

        let qualified = try #require(makeShape(of: "@Persistence.DataActor protocol Store {}"))
        #expect(qualified.globalActorName == "Persistence.DataActor")

        let unsafe = try #require(makeShape(of: "@MainActor(unsafe) protocol ViewModel {}"))
        #expect(unsafe.globalActorName == "MainActor")
    }

    @Test("Attributes that are not global actors are ignored")
    func nonActorAttributesIgnored() throws {
        let shape = try #require(makeShape(of: """
            @Mockable(condition: .debug)
            @Mockable
            @Sendable
            @preconcurrency
            @objc
            @available(iOS 13, *)
            protocol Service {}
            """))
        #expect(shape.globalActorName == nil)
        #expect(shape.isSendable)
    }

    @Test("A global actor attribute inside a conditional-compilation block is not read")
    func conditionalGlobalActorIgnored() throws {
        let shape = try #require(makeShape(of: """
            #if DEBUG
            @MainActor
            #endif
            protocol Service {}
            """))
        #expect(shape.globalActorName == nil)
    }

    @Test("Marker conformances are excluded from parent protocols")
    func markerConformancesExcluded() throws {
        let shape = try #require(makeShape(of: "protocol Service: BaseService, Sendable, AnyObject {}"))
        #expect(shape.parentProtocolNames == ["BaseService"])
        #expect(shape.parentMockClassName == "BaseServiceMock")
        #expect(shape.isSendable)
    }

    @Test("The first of several parents names the mock superclass")
    func firstParentWins() throws {
        let shape = try #require(makeShape(of: "protocol Service: Alpha, Beta {}"))
        #expect(shape.parentProtocolNames == ["Alpha", "Beta"])
        #expect(shape.parentMockClassName == "AlphaMock")
    }

    @Test("The declared access level is read from the modifiers")
    func accessLevelExtraction() throws {
        let publicShape = try #require(makeShape(of: "public protocol Service {}"))
        #expect(publicShape.accessLevel == .public)

        let privateShape = try #require(makeShape(of: "private protocol Service {}"))
        #expect(privateShape.accessLevel == .private)
    }
}
