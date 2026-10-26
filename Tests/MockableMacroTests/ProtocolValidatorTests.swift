import SwiftSyntax
import Testing

@testable import MockableMacros

@Suite("Protocol Validator Tests")
struct ProtocolValidatorTests {
    private func requirement(_ source: String) -> Requirement {
        let decl: DeclSyntax = "\(raw: source)"
        return Requirement(decl)
    }

    private func findings(ofProtocol source: String) throws -> [ProtocolValidator.Finding] {
        let decl: DeclSyntax = "\(raw: source)"
        let protocolDecl = try #require(decl.as(ProtocolDeclSyntax.self))
        return ProtocolValidator.findings(in: ProtocolShape(protocolDecl), members: protocolDecl.memberBlock.members)
    }

    // MARK: - Rules

    @Test("A mockable requirement passes every rule")
    func mockableRequirementPasses() {
        for source in [
            "func fetch(id: Int) async throws -> String",
            "init(name: String)",
            "var name: String { get }",
            "subscript(index: Int) -> Int { get }",
            "associatedtype Item",
            "associatedtype Item: Decodable = Data",
            "typealias Pair = (Int, Int)",
        ] {
            #expect(ProtocolValidator.findings(for: requirement(source)).isEmpty, "\(source)")
        }
    }

    @Test("A member kind the macro cannot mock is reported as unsupported")
    func unsupportedKind() throws {
        let nested = ProtocolValidator.unsupportedKind(requirement("struct Nested {}"))
        #expect(nested.map(\.diagnostic.message) == ["Unsupported protocol member: struct Nested {}"])

        let staticSubscript = ProtocolValidator.unsupportedKind(requirement("static subscript(index: Int) -> Int { get }"))
        #expect(staticSubscript.map(\.diagnostic.message) == ["Unsupported protocol member: static subscript(index: Int) -> Int { get }"])

        #expect(ProtocolValidator.unsupportedKind(requirement("subscript(index: Int) -> Int { get }")).isEmpty)
    }

    @Test("Operators and escaped names are reported, one finding per bound name")
    func unsupportedName() {
        let operatorName = ProtocolValidator.unsupportedName(requirement("static func == (lhs: Self, rhs: Self) -> Bool"))
        #expect(operatorName.map(\.diagnostic.message) == ["Cannot mock '==': operator requirements are not supported"])

        let escaped = ProtocolValidator.unsupportedName(requirement("var `default`: Int { get }"))
        #expect(escaped.map(\.diagnostic.message) == ["Cannot mock '`default`': only requirements whose name is a plain identifier can be mocked"])

        #expect(ProtocolValidator.unsupportedName(requirement("func fetch()")).isEmpty)
    }

    @Test("An autoclosure's effects must be covered by its requirement")
    func uncoveredAutoclosureEffects() {
        let uncovered = ProtocolValidator.uncoveredAutoclosureEffects(
            requirement("func log(_ message: @autoclosure () async throws -> String)")
        )
        #expect(uncovered.map(\.diagnostic.message) == [
            "Cannot mock @autoclosure parameter 'message': the mock evaluates autoclosure arguments when called, so the requirement must be declared 'throws' and 'async'",
        ])

        let covered = ProtocolValidator.uncoveredAutoclosureEffects(
            requirement("func log(_ message: @autoclosure () async throws -> String) async throws")
        )
        #expect(covered.isEmpty)

        let inSubscript = ProtocolValidator.uncoveredAutoclosureEffects(
            requirement("subscript(key: @autoclosure () throws -> String) -> Int { get }")
        )
        #expect(inSubscript.map(\.diagnostic.message) == [
            "Cannot mock @autoclosure parameter 'key': effectful autoclosures are not supported in subscript requirements",
        ])
    }

    @Test("A generic parameter inside a returned function type cannot be cast back")
    func genericFunctionTypeReturn() {
        let unsupported = ProtocolValidator.genericFunctionTypeReturn(requirement("func makeSetter<T>() -> (T) -> Void"))
        #expect(unsupported.count == 1)
        #expect(unsupported.first?.diagnostic.message.hasPrefix("Cannot mock 'makeSetter': its return type '(T) -> Void'") == true)

        #expect(ProtocolValidator.genericFunctionTypeReturn(requirement("func make<T>() -> T")).isEmpty)
        #expect(ProtocolValidator.genericFunctionTypeReturn(requirement("func make() -> (Int) -> Void")).isEmpty)
    }

    @Test("A closure parameter whose own parameters are generic cannot be forwarded")
    func genericClosureParameters() {
        let unsupported = ProtocolValidator.genericClosureParameters(requirement("func observe<T>(_ handler: (T) -> Void)"))
        #expect(unsupported.count == 1)
        #expect(unsupported.first?.diagnostic.message.hasPrefix("Cannot mock 'observe': the parameter 'handler'") == true)

        #expect(ProtocolValidator.genericClosureParameters(requirement("func load<T>(_ make: () -> T)")).isEmpty)
    }

    @Test("A constrained associated type needs a default")
    func constrainedAssociatedType() {
        let constrained = ProtocolValidator.constrainedAssociatedType(requirement("associatedtype Item: Decodable"))
        #expect(constrained.map(\.diagnostic.message) == [
            "Cannot mock associated type 'Item': the mock fulfills it with 'Any', which does not satisfy its constraints. Give it a default ('associatedtype Item: ... = SomeType') so the mock has a type to use.",
        ])

        #expect(ProtocolValidator.constrainedAssociatedType(requirement("associatedtype Item: Decodable = Data")).isEmpty)
        #expect(ProtocolValidator.constrainedAssociatedType(requirement("associatedtype Item")).isEmpty)
    }

    @Test("A requirement failing several rules is reported for the first one only")
    func firstRuleWins() {
        // An operator name fails the name rule; its uncovered throwing autoclosure
        // would fail the autoclosure rule too, but is not reported.
        let findings = ProtocolValidator.findings(
            for: requirement("static func == (lhs: @autoclosure () throws -> Self, rhs: Self) -> Bool")
        )
        #expect(findings.map(\.diagnostic.message) == ["Cannot mock '==': operator requirements are not supported"])
    }

    // MARK: - Protocol-level checks

    @Test("Findings are reported in declaration order, every conditional clause included")
    func declarationOrder() throws {
        let findings = try findings(ofProtocol: """
        protocol Service {
            func fetch()
            #if FLAG
            struct Nested {}
            #else
            associatedtype Item: Decodable
            #endif
            var `default`: Int { get }
        }
        """)

        #expect(findings.map(\.diagnostic.message) == [
            "Unsupported protocol member: struct Nested {}",
            "Cannot mock associated type 'Item': the mock fulfills it with 'Any', which does not satisfy its constraints. Give it a default ('associatedtype Item: ... = SomeType') so the mock has a type to use.",
            "Cannot mock '`default`': only requirements whose name is a plain identifier can be mocked",
        ])
    }

    @Test("Unsupported inherited types are reported after the requirements")
    func inheritedTypes() throws {
        let findings = try findings(ofProtocol: """
        protocol Token: Hashable {
            struct Nested {}
        }
        """)

        #expect(findings.count == 2)
        #expect(findings[0].diagnostic.message == "Unsupported protocol member: struct Nested {}")
        #expect(findings[1].diagnostic.message.hasPrefix("'Hashable' declares requirements @Mockable cannot generate witnesses for"))
    }

    @Test("An init requirement is reported only on a protocol whose mock subclasses a parent mock")
    func initializerOnInheritingProtocol() throws {
        let inheriting = try findings(ofProtocol: """
        protocol Child: Parent {
            init(name: String)
        }
        """)
        #expect(inheriting.map(\.diagnostic.message) == [
            "init requirements declared on an inheriting protocol are not yet supported",
        ])

        let standalone = try findings(ofProtocol: """
        protocol Service {
            init(name: String)
        }
        """)
        #expect(standalone.isEmpty)

        // An actor mock never subclasses, so its inherited protocols are not parents.
        let actor = try findings(ofProtocol: """
        protocol Worker: Parent, Actor {
            init(name: String)
        }
        """)
        #expect(actor.isEmpty)
    }

    @Test("A valid protocol has no findings")
    func validProtocol() throws {
        let findings = try findings(ofProtocol: """
        protocol Service: Sendable {
            associatedtype Item = Int
            init(name: String)
            var name: String { get set }
            func fetch(id: Int) async throws -> Item
            subscript(index: Int) -> Item { get }
        }
        """)

        #expect(findings.isEmpty)
    }
}
