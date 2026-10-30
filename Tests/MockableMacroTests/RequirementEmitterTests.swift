import SwiftSyntax
import Testing

@testable import MockableMacros

@Suite("Requirement Emitter Tests")
struct RequirementEmitterTests {
    /// A generator for the given protocol source.
    private func generator(forProtocol source: String) throws -> MockGenerator {
        let decl: DeclSyntax = "\(raw: source)"
        let protocolDecl = try #require(decl.as(ProtocolDeclSyntax.self))
        return MockGenerator(shape: ProtocolShape(protocolDecl), members: protocolDecl.memberBlock.members)
    }

    @Test("Each kind of witnessed requirement has its own emitter")
    func emitterPerKind() throws {
        let generator = try generator(forProtocol: """
        protocol Service {
            init(id: Int)
            func fetch() -> Int
            var name: String { get }
            subscript(index: Int) -> String { get }
            associatedtype Item
            typealias Identifier = String
        }
        """)
        let emitters = generator.requirements.map { generator.emitter(for: $0) }

        #expect(emitters[0] is InitializerEmitter)
        #expect(emitters[1] is FunctionEmitter)
        #expect(emitters[2] is VariableEmitter)
        #expect(emitters[3] is SubscriptEmitter)
        #expect(emitters[4] == nil)
        #expect(emitters[5] == nil)
    }

    @Test("A property declaration tracks each of its bindings")
    func variableEmitterTracksEveryBinding() throws {
        let generator = try generator(forProtocol: """
        protocol Service {
            var first: Int { get }, second: String { get async }
        }
        """)
        let emitter = try #require(generator.emitter(for: generator.requirements[0]))

        #expect(emitter.trackingRequirements.map(\.identifier) == ["first", "second"])
    }

    @Test("An emitter's members include the tracking slots of its requirement")
    func membersIncludeTrackingSlots() throws {
        let generator = try generator(forProtocol: """
        protocol Service {
            func fetch(id: Int) -> String
        }
        """)
        let emitter = try #require(generator.emitter(for: generator.requirements[0]))
        let memberNames = emitter.members().compactMap { member -> String? in
            if let variable = member.decl.as(VariableDeclSyntax.self) {
                return variable.bindings.first?.pattern.trimmedDescription
            }
            return member.decl.as(FunctionDeclSyntax.self)?.name.text
        }

        #expect(memberNames == ["fetchCallCount", "fetchCallArguments", "fetchHandler", "fetch"])
    }
}
