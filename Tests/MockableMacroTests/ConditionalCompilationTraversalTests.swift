import SwiftSyntax
import Testing

@testable import MockableMacros

@Suite("Conditional Compilation Traversal Tests")
struct ConditionalCompilationTraversalTests {
    /// Builds a generator for the given protocol source, mirroring how
    /// `MockableMacro` constructs one from a parsed declaration.
    private func makeGenerator(
        _ source: String,
        isSendable: Bool = false,
        isActor: Bool = false
    ) -> MockGenerator? {
        let decl: DeclSyntax = "\(raw: source)"
        guard let protocolDecl = decl.as(ProtocolDeclSyntax.self) else {
            return nil
        }
        return MockGenerator(
            protocolName: protocolDecl.name.text,
            mockClassName: MockNaming.mockTypeName(forProtocol: protocolDecl.name.text),
            members: protocolDecl.memberBlock.members,
            isSendable: isSendable,
            isActor: isActor,
            isMainActor: false,
            accessLevel: .internal,
            parentMockClassName: nil
        )
    }

    private let conditionalSource = """
    protocol Service {
        func alpha() -> Int
        #if CUSTOM
        func beta() -> Int
        #else
        func gamma() -> Int
        #endif
    }
    """

    // MARK: - collectDeclsIncludingConditional

    @Test("Members of a conditional clause are collected alongside plain members")
    func collectsConditionalMembers() throws {
        let generator = try #require(makeGenerator("""
        protocol Service {
            func alpha() -> Int
            #if CUSTOM
            func beta() -> Int
            #endif
        }
        """))

        let names = generator.collectDeclsIncludingConditional()
            .compactMap { $0.as(FunctionDeclSyntax.self)?.name.text }
        #expect(names == ["alpha", "beta"])
    }

    @Test("Nested conditional clauses are collected recursively")
    func collectsNestedConditionalMembers() throws {
        let generator = try #require(makeGenerator("""
        protocol Service {
            #if OUTER
            #if INNER
            func nested() -> Int
            #endif
            #endif
        }
        """))

        let names = generator.collectDeclsIncludingConditional()
            .compactMap { $0.as(FunctionDeclSyntax.self)?.name.text }
        #expect(names == ["nested"])
    }

    @Test("Members of an #else clause are collected too")
    func collectsElseClauseMembers() throws {
        // Member generation maps every clause, so the whole-protocol analyses have to
        // see `#else` members as well: otherwise storage, overload grouping, and
        // initializer detection disagree with the members that are emitted.
        let generator = try #require(makeGenerator(conditionalSource))

        let names = generator.collectDeclsIncludingConditional()
            .compactMap { $0.as(FunctionDeclSyntax.self)?.name.text }
        #expect(names == ["alpha", "beta", "gamma"])
    }

    @Test("hasTypeMembers finds a static member declared only in an #else clause")
    func findsStaticMemberInElseClause() throws {
        let generator = try #require(makeGenerator("""
        protocol Service {
            #if CUSTOM
            func alpha() -> Int
            #else
            static func beta() -> Int
            #endif
        }
        """))

        #expect(generator.hasTypeMembers())
    }

    @Test("Overloads are grouped across an #else clause")
    func groupsOverloadsAcrossElseClause() throws {
        let generator = try #require(makeGenerator("""
        protocol Service {
            func fetch(id: Int) -> Int
            #if CUSTOM
            func alpha() -> Int
            #else
            func fetch(name: String) -> Int
            #endif
        }
        """))

        let groups = generator.groupMethodsByNameIncludingConditional()
        #expect(groups["fetch"]?.count == 2)
    }

    @Test("Initializer requirements declared in an #else clause are collected")
    func collectsInitializersInElseClause() throws {
        let generator = try #require(makeGenerator("""
        protocol Service {
            #if CUSTOM
            func alpha() -> Int
            #else
            init(name: String)
            #endif
        }
        """))

        #expect(generator.collectInitializers().count == 1)
        #expect(generator.hasInitializerRequirements)
    }

    // MARK: - groupMethodsByNameIncludingConditional

    @Test("Overloads are grouped across conditional clauses")
    func groupsOverloadsAcrossClauses() throws {
        let generator = try #require(makeGenerator("""
        protocol Service {
            func fetch(id: Int) -> Int
            #if CUSTOM
            func fetch(name: String) -> Int
            #endif
        }
        """))

        let groups = generator.groupMethodsByNameIncludingConditional()
        #expect(groups.count == 1)
        #expect(groups["fetch"]?.count == 2)
    }

    // MARK: - Type-member detection

    @Test("hasTypeMembers finds a static member inside a conditional clause")
    func findsStaticMemberInConditionalClause() throws {
        let generator = try #require(makeGenerator("""
        protocol Service {
            func alpha() -> Int
            #if CUSTOM
            static func beta() -> Int
            #endif
        }
        """))

        #expect(generator.hasTypeMembers())
    }

    @Test("isTypeMember recognizes static and class modifiers")
    func recognizesTypeMemberModifiers() {
        let staticDecl: DeclSyntax = "static func beta() -> Int"
        let classDecl: DeclSyntax = "class func gamma() -> Int"
        let instanceDecl: DeclSyntax = "func alpha() -> Int"
        #expect(MockGenerator.isTypeMember(staticDecl))
        #expect(MockGenerator.isTypeMember(classDecl))
        #expect(!MockGenerator.isTypeMember(instanceDecl))

        let staticVar: DeclSyntax = "static var count: Int { get }"
        let staticSubscript: DeclSyntax = "static subscript(index: Int) -> Int { get }"
        #expect(MockGenerator.isTypeMember(staticVar))
        #expect(MockGenerator.isTypeMember(staticSubscript))

        let associatedType: DeclSyntax = "associatedtype Item"
        #expect(!MockGenerator.isTypeMember(associatedType))
    }

    // MARK: - Storage-model predicates

    @Test("Lock-based storage is used for Sendable and actor mocks and static members")
    func lockBasedStoragePredicates() throws {
        let plain = try #require(makeGenerator("protocol Service {}"))
        #expect(!plain.usesInstanceStorageLock)
        #expect(!plain.usesLockBasedStorage(isTypeMember: false))
        #expect(plain.usesLockBasedStorage(isTypeMember: true))

        let sendable = try #require(makeGenerator("protocol Service {}", isSendable: true))
        #expect(sendable.usesInstanceStorageLock)
        #expect(sendable.usesLockBasedStorage(isTypeMember: false))

        let actor = try #require(makeGenerator("protocol Service {}", isActor: true))
        #expect(actor.usesInstanceStorageLock)
    }

    // MARK: - mapMemberBlockItemsPreservingIfConfig

    @Test("Member mapping preserves the #if structure and visits every clause")
    func memberMappingPreservesStructure() throws {
        let generator = try #require(makeGenerator(conditionalSource))

        let mapped = generator.mapMemberBlockItemsPreservingIfConfig { decl in
            guard let funcDecl = decl.as(FunctionDeclSyntax.self) else {
                return []
            }
            let marker: DeclSyntax = "var \(raw: funcDecl.name.text)Marker: Int"
            return [MemberBlockItemSyntax(decl: marker)]
        }

        #expect(mapped.count == 2)
        #expect(mapped[0].trimmedDescription == "var alphaMarker: Int")

        let ifConfig = try #require(mapped[1].decl.as(IfConfigDeclSyntax.self))
        let rendered = ifConfig.formatted().description
        #expect(rendered.contains("#if CUSTOM"))
        #expect(rendered.contains("var betaMarker: Int"))
        #expect(rendered.contains("#else"))
        #expect(rendered.contains("var gammaMarker: Int"))
    }

    @Test("A conditional clause producing no members is dropped from member mapping")
    func emptyMemberMappingDropsIfConfig() throws {
        let generator = try #require(makeGenerator(conditionalSource))

        let mapped = generator.mapMemberBlockItemsPreservingIfConfig { decl in
            guard decl.as(FunctionDeclSyntax.self)?.name.text == "alpha" else {
                return []
            }
            return [MemberBlockItemSyntax(decl: decl)]
        }

        #expect(mapped.count == 1)
        #expect(mapped[0].decl.is(FunctionDeclSyntax.self))
    }

    // MARK: - mapCodeBlockItemsPreservingIfConfig

    @Test("Statement mapping preserves the #if structure")
    func statementMappingPreservesStructure() throws {
        let generator = try #require(makeGenerator(conditionalSource))

        let mapped = generator.mapCodeBlockItemsPreservingIfConfig { decl in
            guard let funcDecl = decl.as(FunctionDeclSyntax.self) else {
                return []
            }
            let statement: StmtSyntax = "\(raw: funcDecl.name.text)Count = 0"
            return [CodeBlockItemSyntax(item: .stmt(statement))]
        }

        #expect(mapped.count == 2)
        #expect(mapped[0].trimmedDescription == "alphaCount = 0")

        let rendered = mapped[1].formatted().description
        #expect(rendered.contains("#if CUSTOM"))
        #expect(rendered.contains("betaCount = 0"))
        #expect(rendered.contains("#else"))
        #expect(rendered.contains("gammaCount = 0"))
    }

    // MARK: - mapLinesPreservingIfConfig

    @Test("Line mapping renders clause keywords, conditions, and #endif")
    func lineMappingRendersClauses() throws {
        let generator = try #require(makeGenerator(conditionalSource))

        let lines = generator.mapLinesPreservingIfConfig { decl in
            guard let funcDecl = decl.as(FunctionDeclSyntax.self) else {
                return []
            }
            return ["\(funcDecl.name.text)Count = 0"]
        }

        #expect(lines == [
            "alphaCount = 0",
            "#if CUSTOM",
            "betaCount = 0",
            "#else",
            "gammaCount = 0",
            "#endif",
        ])
    }

    @Test("Line mapping returns nothing when no clause produces lines")
    func lineMappingDropsEmptyIfConfig() throws {
        let generator = try #require(makeGenerator("""
        protocol Service {
            #if CUSTOM
            associatedtype Item
            #endif
        }
        """))

        let lines = generator.mapLinesPreservingIfConfig { decl in
            decl.is(FunctionDeclSyntax.self) ? ["marker"] : []
        }

        #expect(lines.isEmpty)
    }

    // MARK: - collectInitializers

    @Test("Initializer requirements are collected across conditional clauses")
    func collectsInitializers() throws {
        let generator = try #require(makeGenerator("""
        protocol Service {
            init()
            #if CUSTOM
            init(name: String)
            #endif
        }
        """))

        #expect(generator.collectInitializers().count == 2)
    }
}
