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

// MARK: - Multiple Subscript Overloads Test Protocol

@Mockable
protocol MultipleSubscriptService {
    subscript(index: Int) -> String { get }
    subscript(key: String) -> Int { get set }
    subscript(row: Int, column: Int) -> Double { get }
}

@Mockable
protocol SendableMultipleSubscriptService: Sendable {
    subscript(index: Int) -> String { get }
    subscript(key: String) -> Int { get set }
}

@Suite("Subscript Mock Tests")
struct SubscriptMockTests {
    @Test("Get-only subscript can be mocked")
    func getOnlySubscript() {
        let mock = SubscriptServiceMock()

        mock.subscriptIntHandler = { index in
            "value at \(index)"
        }

        let result = mock[5]

        #expect(result == "value at 5")
        #expect(mock.subscriptIntCallCount == 1)
        #expect(mock.subscriptIntCallArgs == [5])
    }

    @Test("Get-only subscript tracks multiple calls")
    func getOnlySubscriptMultipleCalls() {
        let mock = SubscriptServiceMock()

        mock.subscriptIntHandler = { index in
            "item \(index)"
        }

        _ = mock[0]
        _ = mock[1]
        _ = mock[2]

        #expect(mock.subscriptIntCallCount == 3)
        #expect(mock.subscriptIntCallArgs == [0, 1, 2])
    }

    @Test("Get-set subscript getter can be mocked")
    func getSetSubscriptGetter() {
        let mock = SubscriptGetSetServiceMock()

        mock.subscriptStringHandler = { key in
            key == "answer" ? 42 : 0
        }

        let result = mock["answer"]

        #expect(result == 42)
        #expect(mock.subscriptStringCallCount == 1)
        #expect(mock.subscriptStringCallArgs == ["answer"])
    }

    @Test("Get-set subscript setter can be mocked")
    func getSetSubscriptSetter() {
        let mock = SubscriptGetSetServiceMock()
        nonisolated(unsafe) var storedValue: (key: String, value: Int)?

        mock.subscriptStringHandler = { _ in 0 }
        mock.subscriptStringSetHandler = { key, newValue in
            storedValue = (key, newValue)
        }

        mock["test"] = 123

        #expect(storedValue?.key == "test")
        #expect(storedValue?.value == 123)
    }

    @Test("Multi-index subscript can be mocked")
    func multiIndexSubscript() {
        let mock = MultiIndexSubscriptServiceMock()

        mock.subscriptIntIntHandler = { args in
            Double(args.row * 10 + args.column)
        }

        let result = mock[2, 3]

        #expect(result == 23.0)
        #expect(mock.subscriptIntIntCallCount == 1)
        #expect(mock.subscriptIntIntCallArgs.count == 1)
        #expect(mock.subscriptIntIntCallArgs[0].row == 2)
        #expect(mock.subscriptIntIntCallArgs[0].column == 3)
    }

    @Test("Multi-index subscript setter can be mocked")
    func multiIndexSubscriptSetter() {
        let mock = MultiIndexSubscriptServiceMock()
        nonisolated(unsafe) var storedValue: (row: Int, column: Int, value: Double)?

        mock.subscriptIntIntHandler = { _ in 0.0 }
        mock.subscriptIntIntSetHandler = { args, newValue in
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
        mock.subscriptIntHandler = { _ in "from mock" }

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

        mock.subscriptIntHandler = { index in
            "value at \(index)"
        }

        let result = mock[5]

        #expect(result == "value at 5")
        #expect(mock.subscriptIntCallCount == 1)
        #expect(mock.subscriptIntCallArgs == [5])
    }

    @Test("Sendable get-set subscript can be mocked")
    func sendableGetSetSubscript() {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = SendableSubscriptGetSetServiceMock()
        nonisolated(unsafe) var storedValue: (key: String, value: Int)?

        mock.subscriptStringHandler = { key in
            key == "test" ? 42 : 0
        }
        mock.subscriptStringSetHandler = { key, newValue in
            storedValue = (key, newValue)
        }

        let getResult = mock["test"]
        mock["key"] = 100

        #expect(getResult == 42)
        #expect(mock.subscriptStringCallCount == 1)
        #expect(storedValue?.key == "key")
        #expect(storedValue?.value == 100)
    }

    @Test("Sendable subscript mock is thread-safe")
    func sendableSubscriptThreadSafety() async {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = SendableSubscriptServiceMock()

        mock.subscriptIntHandler = { index in
            "value \(index)"
        }

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    _ = mock[i]
                }
            }
        }

        #expect(mock.subscriptIntCallCount == 100)
    }
}

// MARK: - Actor Subscript Mock Tests

@Suite("Actor Subscript Mock Tests")
struct ActorSubscriptMockTests {
    @Test("Actor get-only subscript can be mocked")
    func actorGetOnlySubscript() async {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = ActorSubscriptServiceMock()

        mock.subscriptIntHandler = { index in
            "value at \(index)"
        }

        let result = await mock[5]

        #expect(result == "value at 5")
        #expect(mock.subscriptIntCallCount == 1)
        #expect(mock.subscriptIntCallArgs == [5])
    }

    @Test("Actor get-set subscript getter can be mocked")
    func actorGetSetSubscriptGetter() async {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = ActorSubscriptGetSetServiceMock()

        mock.subscriptStringHandler = { key in
            key == "answer" ? 42 : 0
        }

        let result = await mock["answer"]

        #expect(result == 42)
        #expect(mock.subscriptStringCallCount == 1)
        #expect(mock.subscriptStringCallArgs == ["answer"])
    }

    @Test("Actor get-set subscript setter handler can be set")
    func actorGetSetSubscriptSetterHandler() async {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = ActorSubscriptGetSetServiceMock()

        // Verify that setHandler can be set (nonisolated property)
        mock.subscriptStringSetHandler = { _, _ in }

        #expect(mock.subscriptStringSetHandler != nil)
    }

    @Test("Actor subscript mock is thread-safe")
    func actorSubscriptThreadSafety() async {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = ActorSubscriptServiceMock()

        mock.subscriptIntHandler = { index in
            "value \(index)"
        }

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    _ = await mock[i]
                }
            }
        }

        #expect(mock.subscriptIntCallCount == 100)
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

        mock.subscriptIntHandler = { index in
            "value \(index)"
        }

        _ = await mock[1]
        _ = await mock[2]

        #expect(mock.subscriptIntCallCount == 2)
        #expect(mock.subscriptIntCallArgs == [1, 2])

        mock.resetMock()

        #expect(mock.subscriptIntCallCount == 0)
        #expect(mock.subscriptIntCallArgs == [])
        #expect(mock.subscriptIntHandler == nil)
    }
}

// MARK: - Multiple Subscript Overloads Tests

@Suite("Multiple Subscript Overloads Tests")
struct MultipleSubscriptOverloadsTests {
    @Test("Multiple subscript overloads compile and work independently")
    func multipleSubscriptOverloads() {
        let mock = MultipleSubscriptServiceMock()

        // Set up handlers for each subscript type
        mock.subscriptIntHandler = { index in
            "value at \(index)"
        }

        mock.subscriptStringHandler = { key in
            key.count
        }

        mock.subscriptIntIntHandler = { args in
            Double(args.row + args.column)
        }

        // Test Int subscript
        let intResult = mock[5]
        #expect(intResult == "value at 5")
        #expect(mock.subscriptIntCallCount == 1)
        #expect(mock.subscriptIntCallArgs == [5])

        // Test String subscript
        let stringResult = mock["hello"]
        #expect(stringResult == 5)
        #expect(mock.subscriptStringCallCount == 1)
        #expect(mock.subscriptStringCallArgs == ["hello"])

        // Test Int,Int subscript
        let intIntResult = mock[2, 3]
        #expect(intIntResult == 5.0)
        #expect(mock.subscriptIntIntCallCount == 1)
        #expect(mock.subscriptIntIntCallArgs[0].row == 2)
        #expect(mock.subscriptIntIntCallArgs[0].column == 3)
    }

    @Test("Multiple subscript overloads setter works")
    func multipleSubscriptOverloadsSetter() {
        let mock = MultipleSubscriptServiceMock()
        nonisolated(unsafe) var storedValue: Int?

        mock.subscriptStringHandler = { _ in 0 }
        mock.subscriptStringSetHandler = { _, newValue in
            storedValue = newValue
        }

        mock["key"] = 42

        #expect(storedValue == 42)
    }

    @Test("Sendable multiple subscript overloads work")
    func sendableMultipleSubscriptOverloads() {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = SendableMultipleSubscriptServiceMock()

        mock.subscriptIntHandler = { index in
            "item \(index)"
        }

        mock.subscriptStringHandler = { key in
            key.hashValue
        }

        // Test Int subscript
        let intResult = mock[10]
        #expect(intResult == "item 10")
        #expect(mock.subscriptIntCallCount == 1)

        // Test String subscript
        _ = mock["test"]
        #expect(mock.subscriptStringCallCount == 1)
        #expect(mock.subscriptStringCallArgs == ["test"])
    }

    @Test("Multiple subscript overloads can be reset independently")
    func multipleSubscriptOverloadsReset() {
        let mock = MultipleSubscriptServiceMock()

        mock.subscriptIntHandler = { _ in "test" }
        mock.subscriptStringHandler = { _ in 0 }
        mock.subscriptIntIntHandler = { _ in 0.0 }

        _ = mock[1]
        _ = mock[2]
        _ = mock["a"]
        _ = mock[0, 0]

        #expect(mock.subscriptIntCallCount == 2)
        #expect(mock.subscriptStringCallCount == 1)
        #expect(mock.subscriptIntIntCallCount == 1)

        mock.resetMock()

        #expect(mock.subscriptIntCallCount == 0)
        #expect(mock.subscriptIntCallArgs == [])
        #expect(mock.subscriptIntHandler == nil)
        #expect(mock.subscriptStringCallCount == 0)
        #expect(mock.subscriptStringCallArgs == [])
        #expect(mock.subscriptStringHandler == nil)
        #expect(mock.subscriptIntIntCallCount == 0)
        #expect(mock.subscriptIntIntCallArgs.isEmpty)
        #expect(mock.subscriptIntIntHandler == nil)
    }
}
