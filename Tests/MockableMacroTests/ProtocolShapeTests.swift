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
        #expect(!shape.isMainActor)
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
        #expect(!actor.isMainActor)

        let mainActor = try #require(makeShape(of: "@MainActor protocol ViewModel {}"))
        #expect(mainActor.isMainActor)
        #expect(!mainActor.isActor)
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
