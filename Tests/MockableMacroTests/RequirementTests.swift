import SwiftSyntax
import Testing

@testable import MockableMacros

@Suite("Requirement Tests")
struct RequirementTests {
    private func decl(_ source: String) -> DeclSyntax {
        "\(raw: source)"
    }

    private func members(ofProtocol source: String) throws -> MemberBlockItemListSyntax {
        let decl: DeclSyntax = "\(raw: source)"
        return try #require(decl.as(ProtocolDeclSyntax.self)).memberBlock.members
    }

    // MARK: - Classification

    @Test("A function requirement is classified as a function")
    func classifiesFunction() throws {
        let requirement = Requirement(decl("func fetch(id: Int) -> String"))
        guard case .function(let funcDecl) = requirement else {
            Issue.record("expected .function, got \(requirement)")
            return
        }
        #expect(funcDecl.name.text == "fetch")
    }

    @Test("An initializer requirement is classified as an initializer")
    func classifiesInitializer() {
        guard case .initializer = Requirement(decl("init(name: String)")) else {
            Issue.record("expected .initializer")
            return
        }
    }

    @Test("A property requirement is classified as a variable")
    func classifiesVariable() {
        guard case .variable = Requirement(decl("var name: String { get }")) else {
            Issue.record("expected .variable")
            return
        }
    }

    @Test("A subscript requirement is classified as a subscript")
    func classifiesSubscript() {
        guard case .subscript = Requirement(decl("subscript(index: Int) -> Int { get }")) else {
            Issue.record("expected .subscript")
            return
        }
    }

    @Test("An associated type is classified as an associated type")
    func classifiesAssociatedType() {
        guard case .associatedType = Requirement(decl("associatedtype Item")) else {
            Issue.record("expected .associatedType")
            return
        }
    }

    @Test("A type alias is classified as a type alias")
    func classifiesTypeAlias() {
        guard case .typeAlias = Requirement(decl("typealias Pair = (Int, Int)")) else {
            Issue.record("expected .typeAlias")
            return
        }
    }

    @Test("A member kind the macro cannot mock is classified as unsupported")
    func classifiesUnsupported() {
        guard case .unsupported = Requirement(decl("struct Nested {}")) else {
            Issue.record("expected .unsupported")
            return
        }
    }

    @Test("A requirement hands back the declaration it was built from")
    func exposesDeclaration() {
        let source = "func fetch(id: Int) -> String"
        #expect(Requirement(decl(source)).decl.trimmedDescription == source)
    }

    // MARK: - Flattening

    @Test("Requirements are collected in declaration order")
    func collectsInOrder() throws {
        let requirements = Requirement.all(in: try members(ofProtocol: """
        protocol Service {
            associatedtype Item
            init()
            var name: String { get }
            func fetch() -> Item
            subscript(index: Int) -> Item { get }
        }
        """))

        #expect(requirements.map(\.decl.trimmedDescription) == [
            "associatedtype Item",
            "init()",
            "var name: String { get }",
            "func fetch() -> Item",
            "subscript(index: Int) -> Item { get }",
        ])
    }

    @Test("Requirements of every conditional clause are collected, nested blocks included")
    func collectsEveryClause() throws {
        let requirements = Requirement.all(in: try members(ofProtocol: """
        protocol Service {
            func alpha()
            #if FIRST
            func beta()
            #elseif SECOND
            #if INNER
            func gamma()
            #endif
            #else
            func delta()
            #endif
        }
        """))

        #expect(requirements.map(\.decl.trimmedDescription) == [
            "func alpha()",
            "func beta()",
            "func gamma()",
            "func delta()",
        ])
    }

    @Test("A conditional block whose clauses hold no declarations contributes nothing")
    func skipsEmptyClauses() throws {
        let requirements = Requirement.all(in: try members(ofProtocol: """
        protocol Service {
            #if FLAG
            #endif
        }
        """))

        #expect(requirements.isEmpty)
    }
}
