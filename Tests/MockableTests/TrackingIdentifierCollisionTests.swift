import Testing

import Mockable

// Requirements whose suggested tracking identifiers coincide. Compiling these mocks is
// most of the test: before the identifiers were assigned across the whole protocol,
// each pair generated two members of the same name.

/// The parameter type an overload of `load` is named after, so its suggested
/// identifier is `loadItem` — the same one `func loadItem()` suggests.
struct Item: Equatable, Sendable {
    let id: Int
}

@Mockable
protocol CollidingMethodService {
    func load()
    func load(_ item: Item)
    func loadItem()
}

@Mockable
protocol CollidingPropertyService {
    var loadItem: Int { get async }
    func load()
    func load(_ item: Item)
}

@Mockable
protocol CollidingSubscriptService {
    func subscriptString()
    subscript(key: String) -> Int { get }
}

@Mockable
protocol CollidingInitializerService {
    func initString()
    init()
    init(_ name: String)
}

@Mockable
protocol CollidingSendableService: Sendable {
    func load()
    func load(_ item: Item)
    func loadItem()
}

@Suite("Tracking Identifier Collision Integration Tests")
struct TrackingIdentifierCollisionTests {
    @Test("An overload and a method of its suffixed name track independently")
    func methodCollision() {
        let mock = CollidingMethodServiceMock()
        mock.loadHandler = {}
        mock.loadItem2Handler = { _ in }
        mock.loadItemHandler = {}

        mock.load()
        mock.load(Item(id: 1))
        mock.load(Item(id: 2))
        mock.loadItem()
        mock.loadItem()
        mock.loadItem()

        #expect(mock.loadCallCount == 1)
        #expect(mock.loadItem2CallCount == 2)
        #expect(mock.loadItem2CallArgs == [Item(id: 1), Item(id: 2)])
        #expect(mock.loadItemCallCount == 3)

        mock.resetMock()
        #expect(mock.loadCallCount == 0)
        #expect(mock.loadItem2CallCount == 0)
        #expect(mock.loadItemCallCount == 0)
    }

    @Test("A property keeps its identifier and the overload gives way")
    func propertyCollision() async {
        let mock = CollidingPropertyServiceMock()
        mock.loadItemHandler = { 42 }
        mock.loadItem2Handler = { _ in }

        #expect(await mock.loadItem == 42)
        mock.load(Item(id: 9))

        #expect(mock.loadItemCallCount == 1)
        #expect(mock.loadItem2CallArgs == [Item(id: 9)])
    }

    @Test("A subscript gives way to a method named after its identifier")
    func subscriptCollision() {
        let mock = CollidingSubscriptServiceMock()
        mock.subscriptStringHandler = {}
        mock.subscriptString2Handler = { $0.count }

        mock.subscriptString()

        #expect(mock["abc"] == 3)
        #expect(mock.subscriptStringCallCount == 1)
        #expect(mock.subscriptString2CallCount == 1)
        #expect(mock.subscriptString2CallArgs == ["abc"])
    }

    @Test("An initializer gives way to a method named after its identifier")
    func initializerCollision() {
        let mock = CollidingInitializerServiceMock("name")

        #expect(mock.initString2CallCount == 1)
        #expect(mock.initString2CallArgs == ["name"])
        #expect(mock.initCallCount == 0)
        #expect(mock.initStringCallCount == 0)
    }

    @Test("A Sendable mock's lock-backed storage uses the reassigned identifiers")
    func sendableCollision() {
        let mock = CollidingSendableServiceMock()
        mock.loadItem2Handler = { _ in }
        mock.loadItemHandler = {}

        mock.load(Item(id: 1))
        mock.loadItem()

        #expect(mock.loadItem2CallArgs == [Item(id: 1)])
        #expect(mock.loadItemCallCount == 1)

        mock.resetMock()
        #expect(mock.loadItem2CallCount == 0)
        #expect(mock.loadItemCallCount == 0)
    }
}
