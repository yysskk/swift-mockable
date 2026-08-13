import Testing

import Mockable

// Requirements whose parameter names the generated bodies cannot refer to as written.
// Compiling these mocks is most of the test: before the names were normalized, the
// expansions did not parse or silently recorded the wrong value.

@Mockable
protocol WildcardParameterService {
    func handle(_: Int) -> Int
    func pair(_: Int, _: String)
}

@Mockable
protocol KeywordParameterService {
    func value(for: Int) -> Int
    func log(for: Int, in: String)
}

@Mockable
protocol ShadowingParameterService {
    func run(_handler: Int)
    func fetch(fetchCallCount: Int)
}

@Mockable
protocol ShadowingParameterSendableService: Sendable {
    func save(storage: Int)
}

@Mockable
protocol ShadowingParameterStaticService {
    static func store(_staticStorage: Int)
}

@Mockable
protocol NewValueIndexService {
    subscript(newValue: Int) -> String { get set }
}

@Suite("Parameter Name Integration Tests")
struct ParameterNameTests {
    @Test("A wildcard parameter is recorded and forwarded")
    func wildcardParameter() {
        let mock = WildcardParameterServiceMock()
        mock.handleHandler = { $0 * 2 }

        #expect(mock.handle(21) == 42)
        #expect(mock.handleCallCount == 1)
        #expect(mock.handleCallArgs == [21])
    }

    @Test("Several wildcard parameters are recorded under their synthesized labels")
    func severalWildcardParameters() {
        let mock = WildcardParameterServiceMock()
        nonisolated(unsafe) var received: (Int, String)?
        mock.pairHandler = { received = ($0, $1) }

        mock.pair(1, "a")

        #expect(mock.pairCallCount == 1)
        #expect(mock.pairCallArgs.first?.param0 == 1)
        #expect(mock.pairCallArgs.first?.param1 == "a")
        #expect(received?.0 == 1)
        #expect(received?.1 == "a")
    }

    @Test("A keyword parameter keeps its argument label and is recorded")
    func keywordParameter() {
        let mock = KeywordParameterServiceMock()
        mock.valueHandler = { $0 + 1 }

        #expect(mock.value(for: 41) == 42)
        #expect(mock.valueCallArgs == [41])

        mock.logHandler = { _, _ in }
        mock.log(for: 1, in: "scope")

        // The recorded-arguments label is the parameter's own name, unescaped.
        #expect(mock.logCallArgs.first?.for == 1)
        #expect(mock.logCallArgs.first?.in == "scope")
    }

    @Test("A parameter named after a generated local does not capture it")
    func parameterShadowingLocal() {
        let mock = ShadowingParameterServiceMock()
        nonisolated(unsafe) var received: Int?
        mock.runHandler = { received = $0 }

        mock.run(_handler: 7)

        #expect(mock.runCallCount == 1)
        #expect(mock.runCallArgs == [7])
        #expect(received == 7)
    }

    @Test("A parameter named after a tracking member does not capture it")
    func parameterShadowingTrackingMember() {
        let mock = ShadowingParameterServiceMock()
        nonisolated(unsafe) var received: Int?
        mock.fetchHandler = { received = $0 }

        mock.fetch(fetchCallCount: 99)

        // The counter is the mock's own member, not the argument that was passed.
        #expect(mock.fetchCallCount == 1)
        #expect(mock.fetchCallArgs == [99])
        #expect(received == 99)
    }

    @Test("A parameter named after the lock closure's binding is recorded correctly")
    func parameterShadowingStorageBinding() {
        let mock = ShadowingParameterSendableServiceMock()
        mock.saveHandler = { _ in }

        mock.save(storage: 5)

        #expect(mock.saveCallCount == 1)
        #expect(mock.saveCallArgs == [5])
    }

    @Test("A static requirement's parameter named after the storage is recorded correctly")
    func staticParameterShadowingStorage() {
        let mock = ShadowingParameterStaticServiceMock()
        mock.resetMock()
        nonisolated(unsafe) var received: Int?
        ShadowingParameterStaticServiceMock.storeHandler = { received = $0 }

        ShadowingParameterStaticServiceMock.store(_staticStorage: 11)

        #expect(ShadowingParameterStaticServiceMock.storeCallCount == 1)
        #expect(ShadowingParameterStaticServiceMock.storeCallArgs == [11])
        #expect(received == 11)

        mock.resetMock()
    }

    @Test("A subscript index named newValue is distinguished from the value being set")
    func subscriptIndexNamedNewValue() {
        let mock = NewValueIndexServiceMock()
        nonisolated(unsafe) var received: (Int, String)?
        mock.subscriptIntSetHandler = { index, value in received = (index, value) }

        mock[3] = "written"

        #expect(received?.0 == 3)
        #expect(received?.1 == "written")
    }
}
