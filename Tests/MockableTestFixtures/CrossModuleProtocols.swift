import Mockable

// Protocols whose mocks are compiled in this module and exercised from `MockableTests`
// through `@testable import`. Every mock is a plain (non-`Sendable`) class with an
// argument-less method first, so each member after its deprecated `CallArguments` is
// reached across a module boundary, the way an app's mocks are reached from its tests.

@Mockable
@MainActor
protocol CrossModuleWireframe {
    func complete()
    func skip()
}

@Mockable
protocol CrossModuleGate {
    func open()
    func callAsFunction() -> Bool
}

@Mockable
protocol CrossModuleAsyncGate {
    func reset()
    func callAsFunction() async -> Bool
}

enum CrossModuleStatus: Equatable, Sendable {
    case active
    case suspended
}

@Mockable
protocol CrossModuleStore {
    func fetch()
    func clearCache()
    func get() -> CrossModuleStatus?
    func entries() -> [String]
    var name: String { get set }
    subscript(index: Int) -> String { get }
}
