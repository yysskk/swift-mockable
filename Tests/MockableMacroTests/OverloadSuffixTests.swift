import SwiftSyntax
import Testing

@testable import MockableMacros

@Suite("Overload Suffix Tests")
struct OverloadSuffixTests {
    private func functions(_ sources: [String]) -> [FunctionDeclSyntax] {
        sources.map { DeclSyntax(stringLiteral: $0).cast(FunctionDeclSyntax.self) }
    }

    private func initializers(_ sources: [String]) -> [InitializerDeclSyntax] {
        sources.map { DeclSyntax(stringLiteral: "\($0) {}").cast(InitializerDeclSyntax.self) }
    }

    // MARK: - sanitizeTypeName

    @Test(
        "sanitizeTypeName produces identifier-safe spellings",
        arguments: [
            ("Int", "Int"),
            ("Int?", "IntOptional"),
            ("Int!", "IntImplicitlyUnwrapped"),
            ("[Int]", "IntArray"),
            ("[Int]?", "IntArrayOptional"),
            ("[String: Int]", "StringIntArray"),
            ("Dictionary<Int, String>", "DictionaryIntString"),
            ("Array<Set<Int>>", "ArraySetInt"),
            ("(Int, String)", "IntString"),
            ("() -> Void", "Void"),
            ("any Error", "AnyError"),
            ("inout Int", "InoutInt"),
        ]
    )
    func sanitizeTypeName(source: String, expected: String) {
        #expect(OverloadSuffix.sanitizeTypeName(source) == expected)
    }

    // MARK: - Base suffixes

    @Test("A function without parameters has an empty base suffix")
    func emptyParameterBaseSuffix() {
        let funcDecl = functions(["func fetch() -> Int"])[0]
        #expect(OverloadSuffix.functionIdentifierSuffix(from: funcDecl, in: [funcDecl]) == "")
    }

    @Test("Overloads with the same labels are told apart by their parameter types")
    func baseSuffixJoinsParameterTypes() {
        let group = functions([
            "func set(_ value: Bool, forKey: Key) -> Int",
            "func set(_ value: Int, forKey: Key) -> Int",
        ])
        #expect(OverloadSuffix.functionIdentifierSuffix(from: group[0], in: group) == "BoolKey")
        #expect(OverloadSuffix.functionIdentifierSuffix(from: group[1], in: group) == "IntKey")
    }

    // MARK: - Argument labels

    @Test("Overloads with distinct labels are told apart by their labels")
    func distinctLabels() {
        let group = functions([
            "func fetch(id: Int) -> Int",
            "func fetch(name: String) -> Int",
            "func fetch(index: Int) -> Int",
        ])
        #expect(group.map { OverloadSuffix.functionIdentifierSuffix(from: $0, in: group) } == ["ID", "Name", "Index"])
    }

    @Test("An unlabeled or parameterless overload contributes no label")
    func unlabeledOverloads() {
        let group = functions([
            "func load()",
            "func load(from url: URL)",
        ])
        #expect(group.map { OverloadSuffix.functionIdentifierSuffix(from: $0, in: group) } == ["", "From"])
    }

    @Test("Overloads whose labels coincide fall back to types among themselves only")
    func labelCollisionFallsBackToTypes() {
        let group = functions([
            "func fetch(id: Int) -> Int",
            "func fetch(id: String) -> Int",
            "func fetch(name: String) -> Int",
        ])
        #expect(group.map { OverloadSuffix.functionIdentifierSuffix(from: $0, in: group) } == ["Int", "String", "Name"])
    }

    @Test("Every label of a signature joins the suffix")
    func multipleLabels() {
        let group = functions([
            "func move(from source: Int, to destination: Int)",
            "func move(by offset: Int)",
        ])
        #expect(group.map { OverloadSuffix.functionIdentifierSuffix(from: $0, in: group) } == ["FromTo", "By"])
    }

    @Test(
        "A label is capitalized, and a leading acronym uppercased",
        arguments: [
            ("id", "ID"),
            ("url", "URL"),
            ("urlString", "URLString"),
            ("httpHeader", "HTTPHeader"),
            ("forKey", "ForKey"),
            ("identifier", "Identifier"),
            ("uiImage", "UIImage"),
            ("x", "X"),
        ]
    )
    func capitalizedLabel(label: String, expected: String) {
        #expect(OverloadSuffix.capitalizedLabel(label) == expected)
    }

    @Test("A subscript suffix is built from its parameter types, even for a sole subscript")
    func subscriptSuffix() {
        let subscriptDecl = DeclSyntax(stringLiteral: "subscript(key: String) -> Int { get }")
            .cast(SubscriptDeclSyntax.self)
        #expect(OverloadSuffix.subscriptIdentifierSuffix(from: subscriptDecl, in: [subscriptDecl]) == "String")

        let emptyDecl = DeclSyntax(stringLiteral: "subscript() -> Int { get }")
            .cast(SubscriptDeclSyntax.self)
        #expect(OverloadSuffix.subscriptIdentifierSuffix(from: emptyDecl, in: [emptyDecl]) == "")
    }

    // MARK: - Group disambiguation: functions

    @Test("Distinct base suffixes need no further disambiguation")
    func distinctBaseSuffixes() {
        let group = functions([
            "func fetch(_ id: Int) -> Int",
            "func fetch(_ name: String) -> Int",
        ])
        #expect(OverloadSuffix.functionIdentifierSuffix(from: group[0], in: group) == "Int")
        #expect(OverloadSuffix.functionIdentifierSuffix(from: group[1], in: group) == "String")
    }

    @Test("Colliding base suffixes are extended with the return type")
    func returnTypeDisambiguation() {
        let group = functions([
            "func fetch(id: Int) -> Int",
            "func fetch(id: Int) -> Bool",
        ])
        #expect(OverloadSuffix.functionIdentifierSuffix(from: group[0], in: group) == "IntInt")
        #expect(OverloadSuffix.functionIdentifierSuffix(from: group[1], in: group) == "IntBool")
    }

    @Test("A Void return type is not appended to the extended suffix")
    func voidReturnNotAppended() {
        let group = functions([
            "func run(job: Job)",
            "func run(job: Job) async",
        ])
        #expect(OverloadSuffix.functionIdentifierSuffix(from: group[0], in: group) == "Job")
        #expect(OverloadSuffix.functionIdentifierSuffix(from: group[1], in: group) == "JobAsync")
    }

    @Test("Effects disambiguate overloads with identical parameters and return types")
    func effectsDisambiguation() {
        let group = functions([
            "func load(id: Int) -> Data",
            "func load(id: Int) async throws -> Data",
        ])
        #expect(OverloadSuffix.functionIdentifierSuffix(from: group[0], in: group) == "IntData")
        #expect(OverloadSuffix.functionIdentifierSuffix(from: group[1], in: group) == "IntDataAsyncThrowing")
    }

    @Test("A rethrows overload counts as throwing in the extended suffix")
    func rethrowsCountsAsThrowing() {
        let group = functions([
            "func run(_ body: () throws -> Void)",
            "func run(_ body: () throws -> Void) rethrows",
        ])
        #expect(OverloadSuffix.functionIdentifierSuffix(from: group[0], in: group) == "ThrowsVoid")
        #expect(OverloadSuffix.functionIdentifierSuffix(from: group[1], in: group) == "ThrowsVoidThrowing")
    }

    @Test("Overloads colliding after extension get a source-order ordinal")
    func ordinalDisambiguation() {
        // Foo<Bar, Baz> and Foo<BarBaz> sanitize to the same "FooBarBaz".
        let group = functions([
            "func make(value: Foo<Bar, Baz>) -> Int",
            "func make(value: Foo<BarBaz>) -> Int",
        ])
        #expect(OverloadSuffix.functionIdentifierSuffix(from: group[0], in: group) == "FooBarBazInt")
        #expect(OverloadSuffix.functionIdentifierSuffix(from: group[1], in: group) == "FooBarBazInt2")
    }

    @Test("A function outside any collision keeps its base suffix in a mixed group")
    func mixedGroupKeepsBaseSuffix() {
        let group = functions([
            "func fetch(id: Int) -> Int",
            "func fetch(id: Int) -> Bool",
            "func fetch(id: String) -> Int",
        ])
        #expect(OverloadSuffix.functionIdentifierSuffix(from: group[2], in: group) == "String")
    }

    // MARK: - Group disambiguation: initializers

    @Test("Initializer suffixes mirror the function algorithm without a return type")
    func initializerSuffixes() {
        let labeled = initializers([
            "init(host: String)",
            "init(host: String, port: Int)",
        ])
        #expect(OverloadSuffix.initializerIdentifierSuffix(from: labeled[0], in: labeled) == "Host")
        #expect(OverloadSuffix.initializerIdentifierSuffix(from: labeled[1], in: labeled) == "HostPort")

        let unlabeled = initializers([
            "init(_ host: String)",
            "init(_ port: Int)",
        ])
        #expect(OverloadSuffix.initializerIdentifierSuffix(from: unlabeled[0], in: unlabeled) == "String")
        #expect(OverloadSuffix.initializerIdentifierSuffix(from: unlabeled[1], in: unlabeled) == "Int")
    }

    @Test("Colliding initializers are disambiguated by effects, then ordinal")
    func initializerCollisions() {
        let effectGroup = initializers([
            "init(host: String)",
            "init(host: String) async",
        ])
        #expect(OverloadSuffix.initializerIdentifierSuffix(from: effectGroup[0], in: effectGroup) == "String")
        #expect(OverloadSuffix.initializerIdentifierSuffix(from: effectGroup[1], in: effectGroup) == "StringAsync")

        let ordinalGroup = initializers([
            "init(value: Foo<Bar, Baz>)",
            "init(value: Foo<BarBaz>)",
        ])
        #expect(OverloadSuffix.initializerIdentifierSuffix(from: ordinalGroup[0], in: ordinalGroup) == "FooBarBaz")
        #expect(OverloadSuffix.initializerIdentifierSuffix(from: ordinalGroup[1], in: ordinalGroup) == "FooBarBaz2")
    }

    // MARK: - initializerIdentifier(for:in:)

    @Test("A sole initializer gets the bare init identifier")
    func soleInitializerIdentifier() {
        let group = initializers(["init(host: String)"])
        #expect(OverloadSuffix.initializerIdentifier(for: group[0], in: group) == "init")
    }

    @Test("Overloaded initializers get suffixed identifiers")
    func overloadedInitializerIdentifiers() {
        let group = initializers([
            "init()",
            "init(host: String)",
        ])
        #expect(OverloadSuffix.initializerIdentifier(for: group[0], in: group) == "init")
        #expect(OverloadSuffix.initializerIdentifier(for: group[1], in: group) == "initHost")
    }
}
