import Testing

import Mockable

// A protocol restating one it refines under a module-qualified name, the way a
// protocol imported from another module is restated so that `@Mockable` can see
// its requirements. `ExternalRepository` stands in for the imported protocol.

protocol ExternalRepository {
    var name: String { get }
    func load(id: Int) async throws -> String
}

@Mockable
protocol QualifiedRepository: MockableTests.ExternalRepository {
    var name: String { get }
    func load(id: Int) async throws -> String
}

@Mockable
protocol QualifiedAdminRepository: MockableTests.ExternalRepository, QualifiedRepository {
    func purge()
}

@Suite("Qualified Conformance Integration Tests")
struct QualifiedConformanceTests {
    @Test("The mock is usable as the qualified protocol")
    func mockConformsToQualifiedProtocol() async throws {
        let mock = QualifiedRepositoryMock()
        mock.name = "users"
        mock.loadHandler = { id in "user-\(id)" }

        let repository: any ExternalRepository = mock
        #expect(repository.name == "users")
        #expect(try await repository.load(id: 7) == "user-7")
        #expect(mock.loadCallArguments == [7])
    }

    @Test("An unqualified parent beside a qualified conformance is still subclassed")
    func unqualifiedParentIsSubclassed() {
        let mock = QualifiedAdminRepositoryMock()
        mock.purge()

        let parent: QualifiedRepositoryMock = mock
        #expect(parent.loadCallCount == 0)
        #expect(mock.purgeCallCount == 1)
    }
}
