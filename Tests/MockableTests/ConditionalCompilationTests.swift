import Foundation
import Testing

import Mockable

@Mockable
protocol ConditionalService {
    func publicMethod() -> String
    var publicValue: Int { get }

    #if DEBUG
    func debugOnlyMethod()
    func debugGetInfo() -> String
    var debugValue: String { get set }
    #endif
}

@Mockable
protocol ConditionalSendableService: Sendable {
    func fetchData() async -> String

    #if DEBUG
    func debugReset() async
    var debugMode: Bool { get set }
    #endif
}

@Suite("Conditional Compilation Integration Tests")
struct ConditionalCompilationTests {
    @Test("Mock with #if DEBUG can be instantiated")
    func mockCanBeInstantiated() {
        let mock = ConditionalServiceMock()
        #expect(mock.publicMethodCallCount == 0)
    }

    @Test("Public methods work normally")
    func publicMethodsWork() {
        let mock = ConditionalServiceMock()

        mock.publicMethodHandler = { "public result" }
        mock._publicValue = 42

        let result = mock.publicMethod()

        #expect(result == "public result")
        #expect(mock.publicMethodCallCount == 1)
        #expect(mock.publicValue == 42)
    }

    #if DEBUG
    @Test("Debug-only methods are available in DEBUG")
    func debugMethodsAvailable() {
        let mock = ConditionalServiceMock()

        mock.debugOnlyMethodHandler = { }
        mock.debugOnlyMethod()

        #expect(mock.debugOnlyMethodCallCount == 1)
    }

    @Test("Debug-only method with return value")
    func debugMethodWithReturnValue() {
        let mock = ConditionalServiceMock()

        mock.debugGetInfoHandler = { "debug info" }

        let result = mock.debugGetInfo()

        #expect(result == "debug info")
        #expect(mock.debugGetInfoCallCount == 1)
    }

    @Test("Debug-only property works")
    func debugPropertyWorks() {
        let mock = ConditionalServiceMock()

        mock.debugValue = "test debug"

        #expect(mock.debugValue == "test debug")
    }

    @Test("Reset clears both public and debug members")
    func resetClearsBothPublicAndDebug() {
        let mock = ConditionalServiceMock()

        mock.publicMethodHandler = { "public" }
        mock._publicValue = 100
        mock.debugOnlyMethodHandler = { }
        mock.debugGetInfoHandler = { "info" }
        mock.debugValue = "debug"

        _ = mock.publicMethod()
        mock.debugOnlyMethod()
        _ = mock.debugGetInfo()

        #expect(mock.publicMethodCallCount == 1)
        #expect(mock.debugOnlyMethodCallCount == 1)
        #expect(mock.debugGetInfoCallCount == 1)

        mock.resetMock()

        #expect(mock.publicMethodCallCount == 0)
        #expect(mock.debugOnlyMethodCallCount == 0)
        #expect(mock.debugGetInfoCallCount == 0)
        #expect(mock._publicValue == nil)
        #expect(mock._debugValue == nil)
    }
    #endif

    @Test("Mock conforms to protocol")
    func mockConformsToProtocol() {
        func useService(_ service: ConditionalService) -> String {
            service.publicMethod()
        }

        let mock = ConditionalServiceMock()
        mock.publicMethodHandler = { "from mock" }

        let result = useService(mock)

        #expect(result == "from mock")
    }
}

@Suite("Conditional Sendable Integration Tests")
struct ConditionalSendableTests {
    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
    @Test("Sendable mock with #if DEBUG can be instantiated")
    func sendableMockCanBeInstantiated() {
        let mock = ConditionalSendableServiceMock()
        #expect(mock.fetchDataCallCount == 0)
    }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
    @Test("Public async method works")
    func publicAsyncMethodWorks() async {
        let mock = ConditionalSendableServiceMock()

        mock.fetchDataHandler = { "fetched data" }

        let result = await mock.fetchData()

        #expect(result == "fetched data")
        #expect(mock.fetchDataCallCount == 1)
    }

    #if DEBUG
    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
    @Test("Debug-only async method works in Sendable mock")
    func debugAsyncMethodWorks() async {
        let mock = ConditionalSendableServiceMock()

        mock.debugResetHandler = { }

        await mock.debugReset()

        #expect(mock.debugResetCallCount == 1)
    }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
    @Test("Debug-only property works in Sendable mock")
    func debugPropertyWorksInSendable() {
        let mock = ConditionalSendableServiceMock()

        mock.debugMode = true

        #expect(mock.debugMode == true)
    }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
    @Test("Reset clears both public and debug members in Sendable mock")
    func resetWorksInSendable() async {
        let mock = ConditionalSendableServiceMock()

        mock.fetchDataHandler = { "data" }
        mock.debugResetHandler = { }
        mock.debugMode = true

        _ = await mock.fetchData()
        await mock.debugReset()

        #expect(mock.fetchDataCallCount == 1)
        #expect(mock.debugResetCallCount == 1)

        mock.resetMock()

        #expect(mock.fetchDataCallCount == 0)
        #expect(mock.debugResetCallCount == 0)
    }
    #endif

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
    @Test("Sendable mock is Sendable")
    func sendableMockIsSendable() async {
        let mock = ConditionalSendableServiceMock()
        mock.fetchDataHandler = { "data" }

        await withTaskGroup(of: String.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    await mock.fetchData()
                }
            }
        }

        #expect(mock.fetchDataCallCount == 10)
    }
}
