import Mockable

@Mockable
protocol CrossModuleStore {
    func fetch()
    func clearCache()
    func get() -> CrossModuleStatus?
    func entries() -> [String]
    var name: String { get set }
    subscript(index: Int) -> String { get }
}
