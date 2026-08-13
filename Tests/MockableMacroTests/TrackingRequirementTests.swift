import SwiftSyntax
import Testing

@testable import MockableMacros

@Suite("Tracking Requirement Tests")
struct TrackingRequirementTests {
    /// Builds a generator plus overload context for the given protocol source and
    /// returns the tracking requirements of every member, in declaration order.
    private func requirements(
        ofProtocol source: String,
        isSendable: Bool = false,
        isActor: Bool = false
    ) -> [TrackingRequirement] {
        let decl: DeclSyntax = "\(raw: source)"
        guard let protocolDecl = decl.as(ProtocolDeclSyntax.self) else {
            return []
        }
        let generator = MockGenerator(
            protocolName: protocolDecl.name.text,
            mockClassName: MockNaming.mockTypeName(forProtocol: protocolDecl.name.text),
            members: protocolDecl.memberBlock.members,
            isSendable: isSendable,
            isActor: isActor,
            isMainActor: false,
            accessLevel: .internal,
            parentMockClassName: nil
        )
        let overloads = generator.makeOverloadContext()
        return generator.collectDeclsIncludingConditional().flatMap {
            generator.trackingRequirements(for: $0, overloads: overloads)
        }
    }

    private func fieldNames(_ requirement: TrackingRequirement, model: StorageModel) -> [String] {
        requirement.trackingFields(model: model).map(\.name)
    }

    // MARK: - Functions

    @Test("A function tracks call count, arguments, and a handler")
    func functionFields() throws {
        let requirement = try #require(requirements(ofProtocol: """
        protocol Service {
            func fetch(id: Int) async throws -> String
        }
        """).first)

        #expect(requirement.identifier == "fetch")
        #expect(!requirement.isTypeMember)
        let fields = requirement.trackingFields(model: .lockBacked)
        #expect(fields.map(\.name) == ["fetchCallCount", "fetchCallArgs", "fetchHandler"])
        #expect(fields.map(\.resetValue) == ["0", "[]", "nil"])
        #expect(fields[0].type.trimmedDescription == "Int")
        #expect(fields[1].type.trimmedDescription == "[Int]")
        #expect(fields[2].type.trimmedDescription == "(@Sendable (Int) async throws -> String)?")
        #expect(fieldNames(requirement, model: .direct) == fieldNames(requirement, model: .lockBacked))
    }

    @Test("Overloaded functions get disambiguated identifiers")
    func overloadedFunctionIdentifiers() {
        let all = requirements(ofProtocol: """
        protocol Service {
            func fetch(id: Int) -> Int
            func fetch(name: String) -> Int
        }
        """)
        #expect(all.map(\.identifier) == ["fetchInt", "fetchString"])
    }

    @Test("A rethrows function's handler drops the throws effect")
    func rethrowsHandler() throws {
        let requirement = try #require(requirements(ofProtocol: """
        protocol Service {
            func run(_ body: () throws -> Void) rethrows
        }
        """).first)
        #expect(requirement.handlerClosureType == "(() throws -> Void) -> Void")
    }

    @Test("Generic parameters are erased in the tracked types")
    func genericErasure() throws {
        let requirement = try #require(requirements(ofProtocol: """
        protocol Service {
            func convert<T>(_ value: T) -> T
        }
        """).first)
        let fields = requirement.trackingFields(model: .lockBacked)
        #expect(fields[1].type.trimmedDescription == "[Any]")
        #expect(requirement.handlerClosureType == "(Any) -> Any")
    }

    @Test("A static function is a type member")
    func staticFunction() throws {
        let requirement = try #require(requirements(ofProtocol: """
        protocol Service {
            static func reset()
        }
        """).first)
        #expect(requirement.isTypeMember)
    }

    // MARK: - Initializers

    @Test("An initializer tracks calls but has no handler")
    func initializerFields() throws {
        let all = requirements(ofProtocol: """
        protocol Service {
            init()
            init(host: String)
        }
        """)
        #expect(all.map(\.identifier) == ["init", "initString"])
        let fields = all[1].trackingFields(model: .lockBacked)
        #expect(fields.map(\.name) == ["initStringCallCount", "initStringCallArgs"])
        #expect(all[1].handlerClosureType == nil)
        #expect(!all[1].isTypeMember)
    }

    // MARK: - Stored variables

    @Test("A non-optional stored variable is backed by an optional _name slot")
    func nonOptionalStoredVariable() throws {
        let requirement = try #require(requirements(ofProtocol: """
        protocol Service {
            var name: String { get set }
        }
        """).first)

        for model in [StorageModel.direct, .lockBacked] {
            let fields = requirement.trackingFields(model: model)
            #expect(fields.map(\.name) == ["_name"])
            #expect(fields[0].type.trimmedDescription == "String?")
            #expect(fields[0].resetValue == "nil")
        }
    }

    @Test("An optional get-set variable is its own storage on the direct path only")
    func optionalGetSetVariable() throws {
        let requirement = try #require(requirements(ofProtocol: """
        protocol Service {
            var theme: Theme? { get set }
        }
        """).first)

        #expect(fieldNames(requirement, model: .direct) == ["theme"])
        #expect(fieldNames(requirement, model: .lockBacked) == ["_theme"])
        #expect(requirement.trackingFields(model: .lockBacked)[0].type.trimmedDescription == "Theme?")
    }

    @Test("An optional get-only variable keeps its _name backing on both paths")
    func optionalGetOnlyVariable() throws {
        let requirement = try #require(requirements(ofProtocol: """
        protocol Service {
            var lastValue: Int? { get }
        }
        """).first)

        #expect(fieldNames(requirement, model: .direct) == ["_lastValue"])
        #expect(fieldNames(requirement, model: .lockBacked) == ["_lastValue"])
    }

    @Test("An implicitly unwrapped optional counts as optional storage")
    func implicitlyUnwrappedOptionalVariable() throws {
        let requirement = try #require(requirements(ofProtocol: """
        protocol Service {
            var token: String! { get set }
        }
        """).first)
        #expect(requirement.trackingFields(model: .lockBacked)[0].type.trimmedDescription == "String!")
        #expect(fieldNames(requirement, model: .direct) == ["token"])
    }

    @Test("Multiple bindings produce one requirement each")
    func multipleBindings() {
        let all = requirements(ofProtocol: """
        protocol Service {
            var first: Int, second: String { get }
        }
        """)
        #expect(all.map(\.identifier) == ["first", "second"])
    }

    // MARK: - Effectful variables

    @Test("An effectful property tracks call count and handler, with no backing")
    func effectfulVariable() throws {
        let requirement = try #require(requirements(ofProtocol: """
        protocol Service {
            var token: String { get async throws }
        }
        """).first)

        for model in [StorageModel.direct, .lockBacked] {
            let fields = requirement.trackingFields(model: model)
            #expect(fields.map(\.name) == ["tokenCallCount", "tokenHandler"])
        }
        #expect(requirement.handlerClosureType == "() async throws -> String")
    }

    @Test("A typed-throws accessor drops the error type from the handler")
    func typedThrowsEffectfulVariable() throws {
        let requirement = try #require(requirements(ofProtocol: """
        protocol Service {
            var config: Config { get throws(ConfigError) }
        }
        """).first)
        #expect(requirement.handlerClosureType == "() throws -> Config")
    }

    // MARK: - Subscripts

    @Test("A sole subscript still gets a typed identifier suffix")
    func soleSubscriptIdentifier() throws {
        let requirement = try #require(requirements(ofProtocol: """
        protocol Service {
            subscript(key: String) -> Int { get }
        }
        """).first)

        #expect(requirement.identifier == "subscriptString")
        #expect(fieldNames(requirement, model: .lockBacked) == [
            "subscriptStringCallCount", "subscriptStringCallArgs", "subscriptStringHandler",
        ])
    }

    @Test("A get-set subscript adds a set handler")
    func getSetSubscript() throws {
        let requirement = try #require(requirements(ofProtocol: """
        protocol Service {
            subscript(index: Int) -> String { get set }
        }
        """).first)

        #expect(fieldNames(requirement, model: .lockBacked) == [
            "subscriptIntCallCount", "subscriptIntCallArgs", "subscriptIntHandler", "subscriptIntSetHandler",
        ])
        // Subscript closure types keep the return type's source trivia (the space
        // before the accessor block); the expansion tests pin the same spelling.
        #expect(requirement.handlerClosureType == "(Int) -> String ")
        #expect(requirement.setHandlerClosureType == "(Int, String ) -> Void")
    }

    @Test("An effectful subscript getter carries its effects in the handler type")
    func effectfulSubscript() throws {
        let requirement = try #require(requirements(ofProtocol: """
        protocol Service {
            subscript(id: Int) -> User { get async throws }
        }
        """).first)
        #expect(requirement.handlerClosureType == "(Int) async throws -> User ")
    }

    // MARK: - Non-tracking members

    @Test("Associated types and type aliases produce no requirements")
    func nonTrackingMembers() {
        let all = requirements(ofProtocol: """
        protocol Service {
            associatedtype Item
            typealias Alias = Int
        }
        """)
        #expect(all.isEmpty)
    }

    // MARK: - Identifier uniqueness across requirements

    /// The tracking identifiers of every requirement, in declaration order.
    private func identifiers(ofProtocol source: String) -> [String] {
        requirements(ofProtocol: source).map(\.identifier)
    }

    @Test("An overload's suffixed identifier gives way to a method of that name")
    func overloadGivesWayToMethodName() {
        #expect(identifiers(ofProtocol: """
        protocol Service {
            func load()
            func load(_ item: Item)
            func loadItem()
        }
        """) == ["load", "loadItem2", "loadItem"])
    }

    @Test("The method of that name keeps its identifier whichever is declared first")
    func overloadGivesWayRegardlessOfOrder() {
        #expect(identifiers(ofProtocol: """
        protocol Service {
            func loadItem()
            func load()
            func load(_ item: Item)
        }
        """) == ["loadItem", "load", "loadItem2"])
    }

    @Test("An overload's suffixed identifier gives way to a property of that name")
    func overloadGivesWayToPropertyName() {
        #expect(identifiers(ofProtocol: """
        protocol Service {
            var loadItem: Int { get async }
            func load()
            func load(_ item: Item)
        }
        """) == ["loadItem", "load", "loadItem2"])
    }

    @Test("A subscript's identifier gives way to a method of that name")
    func subscriptGivesWayToMethodName() {
        #expect(identifiers(ofProtocol: """
        protocol Service {
            func subscriptString()
            subscript(key: String) -> Int { get }
        }
        """) == ["subscriptString", "subscriptString2"])
    }

    @Test("An initializer's identifier gives way to a method of that name")
    func initializerGivesWayToMethodName() {
        #expect(identifiers(ofProtocol: """
        protocol Service {
            func initString()
            init()
            init(_ name: String)
        }
        """) == ["initString", "init", "initString2"])
    }

    @Test("Counting continues past every identifier already taken")
    func countingContinuesPastTakenIdentifiers() {
        #expect(identifiers(ofProtocol: """
        protocol Service {
            func loadItem()
            func loadItem2()
            func load()
            func load(_ item: Item)
        }
        """) == ["loadItem", "loadItem2", "load", "loadItem3"])
    }

    @Test("A collision across conditional clauses is resolved too")
    func collisionAcrossConditionalClauses() {
        #expect(identifiers(ofProtocol: """
        protocol Service {
            func loadItem()
            #if CUSTOM
            func load()
            func load(_ item: Item)
            #endif
        }
        """) == ["loadItem", "load", "loadItem2"])
    }

    @Test("Requirements that do not collide keep the identifiers they suggest")
    func noCollisionKeepsSuggestedIdentifiers() {
        #expect(identifiers(ofProtocol: """
        protocol Service {
            var name: String { get }
            init(name: String)
            func fetch()
            func fetch(id: Int)
            func fetch(name: String) async
            subscript(index: Int) -> String { get }
        }
        """) == ["name", "init", "fetch", "fetchInt", "fetchString", "subscriptInt"])
    }
}
