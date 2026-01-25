import Foundation
import Testing

import Mockable

@Mockable
protocol DataRepository {
    associatedtype Entity
    func fetch(id: String) -> Entity?
    func save(_ entity: Entity)
    func fetchAll() -> [Entity]
}

@Mockable
protocol TypedCache {
    associatedtype Key = String
    associatedtype Value = Int
    func get(key: Key) -> Value?
    func set(key: Key, value: Value)
}

@Mockable
protocol StateContainer {
    associatedtype State = String
    var currentState: State { get }
    var previousState: State? { get set }
}

@Mockable
protocol AsyncItemStore {
    associatedtype Item
    func load(id: String) async throws -> Item
    func store(_ item: Item) async throws
}

@Mockable
protocol BatchService {
    associatedtype Element = Int
    func process(items: [Element]) -> Int
    func transform(item: Element) -> Element
}

@Suite("Associated Type Integration Tests")
struct AssociatedTypeIntegrationTests {
    @Test("Associated type mock can be instantiated")
    func associatedTypeMockCanBeInstantiated() {
        let mock = DataRepositoryMock()
        #expect(mock.fetchCallCount == 0)
        #expect(mock.saveCallCount == 0)
        #expect(mock.fetchAllCallCount == 0)
    }

    @Test("Associated type mock with default types can be instantiated")
    func associatedTypeWithDefaultsCanBeInstantiated() {
        let mock = TypedCacheMock()
        #expect(mock.getCallCount == 0)
        #expect(mock.setCallCount == 0)
    }

    @Test("Associated type fetch method works")
    func associatedTypeFetchMethod() {
        let mock = DataRepositoryMock()

        mock.fetchHandler = { @Sendable id in
            if id == "1" {
                return "Entity 1"
            }
            return nil
        }

        let result1 = mock.fetch(id: "1")
        let result2 = mock.fetch(id: "2")

        #expect(result1 as? String == "Entity 1")
        #expect(result2 == nil)
        #expect(mock.fetchCallCount == 2)
        #expect(mock.fetchCallArgs == ["1", "2"])
    }

    @Test("Associated type save method tracks calls")
    func associatedTypeSaveMethod() {
        let mock = DataRepositoryMock()
        nonisolated(unsafe) var savedEntities: [Any] = []

        mock.saveHandler = { @Sendable entity in
            savedEntities.append(entity)
        }

        mock.save("Entity A")
        mock.save("Entity B")

        #expect(mock.saveCallCount == 2)
        #expect(mock.saveCallArgs.count == 2)
        #expect(savedEntities.count == 2)
    }

    @Test("Associated type fetchAll returns array")
    func associatedTypeFetchAllMethod() {
        let mock = DataRepositoryMock()

        mock.fetchAllHandler = { @Sendable in
            ["Item 1", "Item 2", "Item 3"]
        }

        let result = mock.fetchAll()

        #expect(result.count == 3)
        #expect(mock.fetchAllCallCount == 1)
    }

    @Test("Associated type with default types works correctly")
    func associatedTypeWithDefaultTypes() {
        let mock = TypedCacheMock()

        mock.getHandler = { @Sendable (key: TypedCacheMock.Key) -> TypedCacheMock.Value? in
            if key == "answer" {
                return 42
            }
            return nil
        }

        mock.setHandler = { @Sendable _ in }

        let result = mock.get(key: "answer")
        mock.set(key: "count", value: 100)

        #expect(result == 42)
        #expect(mock.getCallCount == 1)
        #expect(mock.setCallCount == 1)
        #expect(mock.setCallArgs[0].key == "count")
        #expect(mock.setCallArgs[0].value == 100)
    }

    @Test("Associated type in property works")
    func associatedTypeInProperty() {
        let mock = StateContainerMock()

        mock._currentState = "active"
        mock.previousState = "inactive"

        #expect(mock.currentState == "active")
        #expect(mock.previousState == "inactive")
    }

    @Test("Associated type with async throws method")
    func associatedTypeAsyncThrows() async throws {
        let mock = AsyncItemStoreMock()

        mock.loadHandler = { @Sendable id in
            "Loaded: \(id)"
        }

        mock.storeHandler = { @Sendable _ in }

        let result = try await mock.load(id: "123")

        #expect(result as? String == "Loaded: 123")
        #expect(mock.loadCallCount == 1)
        #expect(mock.loadCallArgs == ["123"])
    }

    @Test("Associated type async method can throw")
    func associatedTypeAsyncCanThrow() async {
        let mock = AsyncItemStoreMock()

        mock.loadHandler = { @Sendable _ in
            throw TestError.somethingWentWrong
        }

        do {
            _ = try await mock.load(id: "error")
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(error as? TestError == TestError.somethingWentWrong)
        }
    }

    @Test("Associated type with array parameter")
    func associatedTypeWithArrayParameter() {
        let mock = BatchServiceMock()

        mock.processHandler = { @Sendable items in
            items.reduce(0, +)
        }

        let result = mock.process(items: [1, 2, 3, 4, 5])

        #expect(result == 15)
        #expect(mock.processCallCount == 1)
        #expect(mock.processCallArgs[0] == [1, 2, 3, 4, 5])
    }

    @Test("Associated type transform method")
    func associatedTypeTransformMethod() {
        let mock = BatchServiceMock()

        mock.transformHandler = { @Sendable item in
            item * 2
        }

        let result = mock.transform(item: 5)

        #expect(result == 10)
        #expect(mock.transformCallCount == 1)
        #expect(mock.transformCallArgs == [5])
    }

    @Test("Associated type mock resetMock works")
    func associatedTypeMockResetMock() {
        let mock = DataRepositoryMock()
        mock.fetchHandler = { @Sendable _ in "entity" }
        mock.saveHandler = { @Sendable _ in }
        mock.fetchAllHandler = { @Sendable in [] }

        _ = mock.fetch(id: "1")
        mock.save("entity")
        _ = mock.fetchAll()

        #expect(mock.fetchCallCount == 1)
        #expect(mock.saveCallCount == 1)
        #expect(mock.fetchAllCallCount == 1)

        mock.resetMock()

        #expect(mock.fetchCallCount == 0)
        #expect(mock.fetchCallArgs.isEmpty)
        #expect(mock.fetchHandler == nil)
        #expect(mock.saveCallCount == 0)
        #expect(mock.saveCallArgs.isEmpty)
        #expect(mock.saveHandler == nil)
        #expect(mock.fetchAllCallCount == 0)
        #expect(mock.fetchAllCallArgs.isEmpty)
        #expect(mock.fetchAllHandler == nil)
    }

    @Test("Associated type with default resetMock works")
    func associatedTypeWithDefaultResetMock() {
        let mock = TypedCacheMock()
        mock.getHandler = { @Sendable _ in 42 }
        mock.setHandler = { @Sendable _ in }

        _ = mock.get(key: "key")
        mock.set(key: "key", value: 100)

        mock.resetMock()

        #expect(mock.getCallCount == 0)
        #expect(mock.getCallArgs.isEmpty)
        #expect(mock.setCallCount == 0)
        #expect(mock.setCallArgs.isEmpty)
    }

    @Test("Associated type mock conforms to protocol")
    func associatedTypeMockConformsToProtocol() {
        func useRepository<R: DataRepository>(_ repo: R) -> R.Entity? {
            repo.fetch(id: "test")
        }

        let mock = DataRepositoryMock()
        mock.fetchHandler = { @Sendable _ in "found" }

        let result = useRepository(mock)

        #expect(result as? String == "found")
    }
}
