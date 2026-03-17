import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import MockableMacros

@Suite("MainActor Macro Tests")
struct MainActorMacroTests {
    private let testMacros: [String: Macro.Type] = [
        "Mockable": MockableMacro.self
    ]

    @Test("@MainActor protocol generates @MainActor mock class")
    func mainActorProtocol() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            @MainActor
            protocol Presenter {
                func loadData()
                var title: String { get }
            }
            """,
            expandedSource: """
            @MainActor
            protocol Presenter {
                func loadData()
                var title: String { get }
            }

            #if DEBUG
            @MainActor class PresenterMock: Presenter {
                var loadDataCallCount: Int = 0
                var loadDataCallArgs: [()] = []
                var loadDataHandler: (@Sendable () -> Void)? = nil
                func loadData() {
                    loadDataCallCount += 1
                    loadDataCallArgs.append(())
                    if let _handler = loadDataHandler {
                        _handler()
                    }
                }
                var _title: String? = nil
                var title: String {
                    _title!
                }
                func resetMock() {
                    loadDataCallCount = 0
                    loadDataCallArgs = []
                    loadDataHandler = nil
                    _title = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }

    @Test("@MainActor protocol with async method")
    func mainActorProtocolWithAsyncMethod() {
        assertMacroExpansionForTesting(
            """
            @Mockable
            @MainActor
            protocol AsyncPresenter {
                func fetchItems() async -> [String]
            }
            """,
            expandedSource: """
            @MainActor
            protocol AsyncPresenter {
                func fetchItems() async -> [String]
            }

            #if DEBUG
            @MainActor class AsyncPresenterMock: AsyncPresenter {
                var fetchItemsCallCount: Int = 0
                var fetchItemsCallArgs: [()] = []
                var fetchItemsHandler: (@Sendable () async -> [String])? = nil
                func fetchItems() async -> [String] {
                    fetchItemsCallCount += 1
                    fetchItemsCallArgs.append(())
                    guard let _handler = fetchItemsHandler else {
                        fatalError("\\(Self.self).fetchItemsHandler is not set")
                    }
                    return await _handler()
                }
                func resetMock() {
                    fetchItemsCallCount = 0
                    fetchItemsCallArgs = []
                    fetchItemsHandler = nil
                }
            }
            #endif
            """,
            macros: testMacros
        )
    }
}
