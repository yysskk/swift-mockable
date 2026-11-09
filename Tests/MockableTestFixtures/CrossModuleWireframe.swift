import Mockable

// The mocks in this module are exercised from `MockableTests` through `@testable import`,
// the way an app's tests reach mocks declared in a library. The module spans several
// files, and its production code calls the mocked protocols, so it builds the way such a
// library does.

@Mockable
@MainActor
protocol CrossModuleWireframe {
    func complete()
    func skip()
}
