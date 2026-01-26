import Foundation
import Testing

import Mockable

@Mockable
protocol SubscriptService {
    subscript(index: Int) -> String { get }
}

@Mockable
protocol SubscriptGetSetService {
    subscript(key: String) -> Int { get set }
}

@Mockable
protocol MultiIndexSubscriptService {
    subscript(row: Int, column: Int) -> Double { get set }
}

@Mockable
protocol SendableSubscriptService: Sendable {
    subscript(index: Int) -> String { get }
}

@Mockable
protocol SendableSubscriptGetSetService: Sendable {
    subscript(key: String) -> Int { get set }
}

@Mockable
protocol ActorSubscriptService: Actor {
    subscript(index: Int) -> String { get }
}

@Mockable
protocol ActorSubscriptGetSetService: Actor {
    subscript(key: String) -> Int { get set }
}

@Suite("Subscript Mock Tests")
struct SubscriptMockTests {
    @Test("Get-only subscript can be mocked")
    func getOnlySubscript() {
        let mock = SubscriptServiceMock()

        mock.subscriptHandler = { index in
            "value at \(index)"
        }

        let result = mock[5]

        #expect(result == "value at 5")
        #expect(mock.subscriptCallCount == 1)
        #expect(mock.subscriptCallArgs == [5])
    }

    @Test("Get-only subscript tracks multiple calls")
    func getOnlySubscriptMultipleCalls() {
        let mock = SubscriptServiceMock()

        mock.subscriptHandler = { index in
            "item \(index)"
        }

        _ = mock[0]
        _ = mock[1]
        _ = mock[2]

        #expect(mock.subscriptCallCount == 3)
        #expect(mock.subscriptCallArgs == [0, 1, 2])
    }

    @Test("Get-set subscript getter can be mocked")
    func getSetSubscriptGetter() {
        let mock = SubscriptGetSetServiceMock()

        mock.subscriptHandler = { key in
            key == "answer" ? 42 : 0
        }

        let result = mock["answer"]

        #expect(result == 42)
        #expect(mock.subscriptCallCount == 1)
        #expect(mock.subscriptCallArgs == ["answer"])
    }

    @Test("Get-set subscript setter can be mocked")
    func getSetSubscriptSetter() {
        let mock = SubscriptGetSetServiceMock()
        nonisolated(unsafe) var storedValue: (key: String, value: Int)?

        mock.subscriptHandler = { _ in 0 }
        mock.subscriptSetHandler = { key, newValue in
            storedValue = (key, newValue)
        }

        mock["test"] = 123

        #expect(storedValue?.key == "test")
        #expect(storedValue?.value == 123)
    }

    @Test("Multi-index subscript can be mocked")
    func multiIndexSubscript() {
        let mock = MultiIndexSubscriptServiceMock()

        mock.subscriptHandler = { args in
            Double(args.row * 10 + args.column)
        }

        let result = mock[2, 3]

        #expect(result == 23.0)
        #expect(mock.subscriptCallCount == 1)
        #expect(mock.subscriptCallArgs.count == 1)
        #expect(mock.subscriptCallArgs[0].row == 2)
        #expect(mock.subscriptCallArgs[0].column == 3)
    }

    @Test("Multi-index subscript setter can be mocked")
    func multiIndexSubscriptSetter() {
        let mock = MultiIndexSubscriptServiceMock()
        nonisolated(unsafe) var storedValue: (row: Int, column: Int, value: Double)?

        mock.subscriptHandler = { _ in 0.0 }
        mock.subscriptSetHandler = { args, newValue in
            storedValue = (args.row, args.column, newValue)
        }

        mock[1, 2] = 3.14

        #expect(storedValue?.row == 1)
        #expect(storedValue?.column == 2)
        #expect(storedValue?.value == 3.14)
    }

    @Test("Mock with subscript conforms to protocol")
    func mockConformsToProtocol() {
        func useService(_ service: SubscriptService) -> String {
            service[0]
        }

        let mock = SubscriptServiceMock()
        mock.subscriptHandler = { _ in "from mock" }

        let result = useService(mock)

        #expect(result == "from mock")
    }
}

@Suite("Sendable Subscript Mock Tests")
struct SendableSubscriptMockTests {
    @Test("Sendable get-only subscript can be mocked")
    func sendableGetOnlySubscript() {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = SendableSubscriptServiceMock()

        mock.subscriptHandler = { index in
            "value at \(index)"
        }

        let result = mock[5]

        #expect(result == "value at 5")
        #expect(mock.subscriptCallCount == 1)
        #expect(mock.subscriptCallArgs == [5])
    }

    @Test("Sendable get-set subscript can be mocked")
    func sendableGetSetSubscript() {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = SendableSubscriptGetSetServiceMock()
        nonisolated(unsafe) var storedValue: (key: String, value: Int)?

        mock.subscriptHandler = { key in
            key == "test" ? 42 : 0
        }
        mock.subscriptSetHandler = { key, newValue in
            storedValue = (key, newValue)
        }

        let getResult = mock["test"]
        mock["key"] = 100

        #expect(getResult == 42)
        #expect(mock.subscriptCallCount == 1)
        #expect(storedValue?.key == "key")
        #expect(storedValue?.value == 100)
    }

    @Test("Sendable subscript mock is thread-safe")
    func sendableSubscriptThreadSafety() async {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = SendableSubscriptServiceMock()

        mock.subscriptHandler = { index in
            "value \(index)"
        }

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    _ = mock[i]
                }
            }
        }

        #expect(mock.subscriptCallCount == 100)
    }
}

// MARK: - Actor Subscript Mock Tests

@Suite("Actor Subscript Mock Tests")
struct ActorSubscriptMockTests {
    @Test("Actor get-only subscript can be mocked")
    func actorGetOnlySubscript() async {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = ActorSubscriptServiceMock()

        mock.subscriptHandler = { index in
            "value at \(index)"
        }

        let result = await mock[5]

        #expect(result == "value at 5")
        #expect(mock.subscriptCallCount == 1)
        #expect(mock.subscriptCallArgs == [5])
    }

    @Test("Actor get-set subscript getter can be mocked")
    func actorGetSetSubscriptGetter() async {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = ActorSubscriptGetSetServiceMock()

        mock.subscriptHandler = { key in
            key == "answer" ? 42 : 0
        }

        let result = await mock["answer"]

        #expect(result == 42)
        #expect(mock.subscriptCallCount == 1)
        #expect(mock.subscriptCallArgs == ["answer"])
    }

    @Test("Actor get-set subscript setter handler can be set")
    func actorGetSetSubscriptSetterHandler() async {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = ActorSubscriptGetSetServiceMock()

        // Verify that setHandler can be set (nonisolated property)
        mock.subscriptSetHandler = { _, _ in }

        #expect(mock.subscriptSetHandler != nil)
    }

    @Test("Actor subscript mock is thread-safe")
    func actorSubscriptThreadSafety() async {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = ActorSubscriptServiceMock()

        mock.subscriptHandler = { index in
            "value \(index)"
        }

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    _ = await mock[i]
                }
            }
        }

        #expect(mock.subscriptCallCount == 100)
    }

    @Test("Actor subscript mock conforms to Actor protocol")
    func actorSubscriptConformsToActorProtocol() async {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = ActorSubscriptServiceMock()

        // Verify mock is an actor
        func useActor<T: Actor>(_ actor: T) -> T { actor }
        let result = useActor(mock)
        #expect(result === mock)
    }

    @Test("Actor subscript resetMock works")
    func actorSubscriptResetMock() async {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = ActorSubscriptServiceMock()

        mock.subscriptHandler = { index in
            "value \(index)"
        }

        _ = await mock[1]
        _ = await mock[2]

        #expect(mock.subscriptCallCount == 2)
        #expect(mock.subscriptCallArgs == [1, 2])

        mock.resetMock()

        #expect(mock.subscriptCallCount == 0)
        #expect(mock.subscriptCallArgs == [])
        #expect(mock.subscriptHandler == nil)
    }
}
