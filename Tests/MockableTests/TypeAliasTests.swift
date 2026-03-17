import Foundation
import Testing

import Mockable

@Mockable
protocol CartPresenterDelegate {
    typealias TableViewUpdateType = String
    func didUpdate(type: TableViewUpdateType)
    func currentUpdateType() -> TableViewUpdateType
}

@Mockable
protocol TypeAliasedService {
    typealias Callback = (String) -> Void
    typealias ID = Int
    func register(id: ID, callback: @escaping Callback)
    func unregister(id: ID)
}

@Mockable
protocol TypeAliasWithProperty {
    typealias Value = [String: Any]
    var current: Value { get set }
    func update(with value: Value)
}

@Suite("TypeAlias Integration Tests")
struct TypeAliasIntegrationTests {
    @Test("TypeAlias mock can be instantiated")
    func typeAliasMockCanBeInstantiated() {
        let mock = CartPresenterDelegateMock()
        #expect(mock.didUpdateCallCount == 0)
        #expect(mock.currentUpdateTypeCallCount == 0)
    }

    @Test("TypeAlias void method tracks calls")
    func typeAliasVoidMethodTracking() {
        let mock = CartPresenterDelegateMock()

        mock.didUpdate(type: "insert")
        mock.didUpdate(type: "delete")

        #expect(mock.didUpdateCallCount == 2)
        #expect(mock.didUpdateCallArgs == ["insert", "delete"])
    }

    @Test("TypeAlias return value method with handler")
    func typeAliasReturnValueMethod() {
        let mock = CartPresenterDelegateMock()

        mock.currentUpdateTypeHandler = { @Sendable in
            "reload"
        }

        let result = mock.currentUpdateType()

        #expect(result == "reload")
        #expect(mock.currentUpdateTypeCallCount == 1)
    }

    @Test("TypeAlias mock resetMock works")
    func typeAliasMockResetMock() {
        let mock = CartPresenterDelegateMock()
        mock.currentUpdateTypeHandler = { @Sendable in "test" }

        _ = mock.currentUpdateType()
        mock.didUpdate(type: "insert")

        #expect(mock.currentUpdateTypeCallCount == 1)
        #expect(mock.didUpdateCallCount == 1)

        mock.resetMock()

        #expect(mock.currentUpdateTypeCallCount == 0)
        #expect(mock.currentUpdateTypeCallArgs.isEmpty)
        #expect(mock.currentUpdateTypeHandler == nil)
        #expect(mock.didUpdateCallCount == 0)
        #expect(mock.didUpdateCallArgs.isEmpty)
        #expect(mock.didUpdateHandler == nil)
    }

    @Test("Multiple typealiases work correctly")
    func multipleTypealiases() {
        let mock = TypeAliasedServiceMock()
        nonisolated(unsafe) var registeredCallbacks: [TypeAliasedServiceMock.ID] = []

        mock.registerHandler = { @Sendable args in
            registeredCallbacks.append(args.id)
        }

        mock.register(id: 1, callback: { _ in })
        mock.register(id: 2, callback: { _ in })

        #expect(mock.registerCallCount == 2)
        #expect(registeredCallbacks == [1, 2])
    }

    @Test("TypeAlias with property works")
    func typeAliasWithProperty() {
        let mock = TypeAliasWithPropertyMock()

        mock.current = ["key": "value"]
        mock.updateHandler = { @Sendable _ in }
        mock.update(with: ["new": 42])

        #expect(mock.current["key"] as? String == "value")
        #expect(mock.updateCallCount == 1)
    }

    @Test("TypeAlias mock conforms to protocol")
    func typeAliasMockConformsToProtocol() {
        func useDelegate(_ delegate: some CartPresenterDelegate) -> CartPresenterDelegate.TableViewUpdateType {
            delegate.currentUpdateType()
        }

        let mock = CartPresenterDelegateMock()
        mock.currentUpdateTypeHandler = { @Sendable in "refresh" }

        let result = useDelegate(mock)

        #expect(result == "refresh")
    }
}
