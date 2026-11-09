import Testing

@testable import MockableTestFixtures

// The mocks under test live in `MockableTestFixtures`, so every access below crosses a
// module boundary. Each protocol starts with a method that takes no arguments, whose
// deprecated `CallArguments` is emitted before the members these tests read; the tests
// check that those later members still read and write their own storage.

@Suite("Cross-Module Mock Tests")
struct CrossModuleMockTests {
    @Test("Call counts after an argument-less method are tracked independently")
    @MainActor
    func callCountsAfterArgumentlessMethod() {
        let wireframe = CrossModuleWireframeMock()

        wireframe.skip()

        #expect(wireframe.skipCallCount == 1)
        #expect(wireframe.completeCallCount == 0)
    }

    @Test("A handler after an argument-less method is invoked")
    @MainActor
    func handlerAfterArgumentlessMethod() {
        let wireframe = CrossModuleWireframeMock()
        nonisolated(unsafe) var skipped = false
        wireframe.skipHandler = { skipped = true }

        wireframe.skip()

        #expect(skipped)
    }

    @Test("A callAsFunction handler after an argument-less method is used")
    func callAsFunctionHandler() {
        let gate = CrossModuleGateMock()
        gate.callAsFunctionHandler = { true }

        #expect(gate())
        #expect(gate.callAsFunctionCallCount == 1)
        #expect(gate.openCallCount == 0)
    }

    @Test("An async callAsFunction handler after an argument-less method is used")
    func asyncCallAsFunctionHandler() async {
        let gate = CrossModuleAsyncGateMock()
        gate.callAsFunctionHandler = { true }

        #expect(await gate())
        #expect(gate.callAsFunctionCallCount == 1)
        #expect(gate.resetCallCount == 0)
    }

    @Test("Members after several argument-less methods keep their own values")
    func membersAfterSeveralArgumentlessMethods() {
        let store = CrossModuleStoreMock()
        store.getHandler = { .suspended }
        store.entriesHandler = { ["a", "b"] }
        store.name = "cache"
        store.subscriptIntHandler = { index in "item\(index)" }

        store.fetch()
        store.clearCache()
        store.clearCache()

        #expect(store.fetchCallCount == 1)
        #expect(store.clearCacheCallCount == 2)
        #expect(store.get() == .suspended)
        #expect(store.getCallCount == 1)
        #expect(store.entries() == ["a", "b"])
        #expect(store.name == "cache")
        #expect(store[3] == "item3")
        #expect(store.subscriptIntCallArguments == [3])
    }

    @Test("The deprecated CallArguments still mirrors the call count across modules")
    @available(*, deprecated)
    func deprecatedCallArgumentsAcrossModules() {
        let store = CrossModuleStoreMock()

        store.clearCache()
        store.clearCache()

        #expect(store.clearCacheCallArguments.count == 2)
        #expect(store.fetchCallArguments.isEmpty)
    }

    @Test("Production code in the mock's module records calls a test reads from another module")
    @MainActor
    func presenterRecordsCallsReadFromAnotherModule() {
        let view = CrossModuleViewMock()
        let wireframe = CrossModuleWireframeMock()
        let presenter = CrossModulePresenter(view: view, wireframe: wireframe)

        presenter.didAppear()
        presenter.didTapClose()

        #expect(view.showLoadingCallCount == 1)
        #expect(view.showCallArguments == ["Title"])
        #expect(wireframe.skipCallCount == 1)
        #expect(wireframe.completeCallCount == 0)
    }

    @Test("Handlers a test sets are used by production code in the mock's module")
    func interactorUsesHandlersSetFromAnotherModule() async {
        let gate = CrossModuleGateMock()
        let asyncGate = CrossModuleAsyncGateMock()
        let store = CrossModuleStoreMock()
        gate.callAsFunctionHandler = { true }
        asyncGate.callAsFunctionHandler = { true }
        store.entriesHandler = { ["a"] }
        store.getHandler = { .active }
        let interactor = CrossModuleInteractor(gate: gate, asyncGate: asyncGate, store: store)

        #expect(interactor.isOpen())
        #expect(await interactor.isOpenAsync())
        #expect(interactor.refresh() == ["a"])
        #expect(interactor.status() == .active)
        #expect(store.fetchCallCount == 1)
        #expect(store.clearCacheCallCount == 1)
    }
}
