/// Production code calling mocked protocols from a different file than the mocks.
final class CrossModuleInteractor {
    private let gate: any CrossModuleGate
    private let asyncGate: any CrossModuleAsyncGate
    private let store: any CrossModuleStore

    init(gate: any CrossModuleGate, asyncGate: any CrossModuleAsyncGate, store: any CrossModuleStore) {
        self.gate = gate
        self.asyncGate = asyncGate
        self.store = store
    }

    func isOpen() -> Bool {
        gate()
    }

    func isOpenAsync() async -> Bool {
        await asyncGate()
    }

    func refresh() -> [String] {
        store.fetch()
        store.clearCache()
        return store.entries()
    }

    func status() -> CrossModuleStatus? {
        store.get()
    }
}
