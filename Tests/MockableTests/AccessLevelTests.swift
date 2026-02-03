import Foundation
import Testing

import Mockable

// MARK: - Access Level Test Protocols

// Internal protocol (no explicit modifier) - should generate internal mock
@Mockable
protocol InternalUserService {
    func fetchUser(id: Int) -> String
    var currentUser: String { get }
}

// Public protocol - should generate public mock
@Mockable
public protocol PublicConfigService {
    func getConfig(key: String) -> String
    var environment: String { get set }
}

// Package protocol - should generate package mock
@Mockable
package protocol PackageDataService {
    func loadData() -> Data?
    var isReady: Bool { get }
}

// MARK: - Tests

@Suite("Access Level Integration Tests")
struct AccessLevelIntegrationTests {
    @Test("Internal protocol mock can be instantiated and used")
    func internalProtocolMock() {
        let mock = InternalUserServiceMock()

        mock.fetchUserHandler = { @Sendable id in
            "User \(id)"
        }
        mock._currentUser = "John"

        let result = mock.fetchUser(id: 42)

        #expect(result == "User 42")
        #expect(mock.fetchUserCallCount == 1)
        #expect(mock.fetchUserCallArgs == [42])
        #expect(mock.currentUser == "John")
    }

    @Test("Internal protocol mock conforms to protocol")
    func internalProtocolConformance() {
        func useService(_ service: InternalUserService) -> String {
            service.fetchUser(id: 1)
        }

        let mock = InternalUserServiceMock()
        mock.fetchUserHandler = { @Sendable _ in "mocked" }

        let result = useService(mock)

        #expect(result == "mocked")
    }

    @Test("Public protocol mock can be instantiated and used")
    func publicProtocolMock() {
        let mock = PublicConfigServiceMock()

        mock.getConfigHandler = { @Sendable key in
            "value for \(key)"
        }
        mock._environment = "production"

        let result = mock.getConfig(key: "api_url")

        #expect(result == "value for api_url")
        #expect(mock.getConfigCallCount == 1)
        #expect(mock.getConfigCallArgs == ["api_url"])
        #expect(mock.environment == "production")
    }

    @Test("Public protocol mock conforms to protocol")
    func publicProtocolConformance() {
        func useConfig(_ service: PublicConfigService) -> String {
            service.getConfig(key: "test")
        }

        let mock = PublicConfigServiceMock()
        mock.getConfigHandler = { @Sendable _ in "public config" }

        let result = useConfig(mock)

        #expect(result == "public config")
    }

    @Test("Package protocol mock can be instantiated and used")
    func packageProtocolMock() {
        let mock = PackageDataServiceMock()

        mock.loadDataHandler = { @Sendable in
            Data([0x01, 0x02, 0x03])
        }
        mock._isReady = true

        let result = mock.loadData()

        #expect(result == Data([0x01, 0x02, 0x03]))
        #expect(mock.loadDataCallCount == 1)
        #expect(mock.isReady == true)
    }

    @Test("Package protocol mock conforms to protocol")
    func packageProtocolConformance() {
        func useDataService(_ service: PackageDataService) -> Bool {
            service.isReady
        }

        let mock = PackageDataServiceMock()
        mock._isReady = true

        let result = useDataService(mock)

        #expect(result == true)
    }

    @Test("Internal protocol mock reset works")
    func internalProtocolReset() {
        let mock = InternalUserServiceMock()

        mock.fetchUserHandler = { @Sendable _ in "user" }
        _ = mock.fetchUser(id: 1)
        _ = mock.fetchUser(id: 2)
        mock._currentUser = "Jane"

        #expect(mock.fetchUserCallCount == 2)
        #expect(mock.fetchUserCallArgs == [1, 2])

        mock.resetMock()

        #expect(mock.fetchUserCallCount == 0)
        #expect(mock.fetchUserCallArgs == [])
        #expect(mock.fetchUserHandler == nil)
        #expect(mock._currentUser == nil)
    }

    @Test("Public protocol mock reset works")
    func publicProtocolReset() {
        let mock = PublicConfigServiceMock()

        mock.getConfigHandler = { @Sendable _ in "config" }
        _ = mock.getConfig(key: "a")
        mock._environment = "test"

        #expect(mock.getConfigCallCount == 1)

        mock.resetMock()

        #expect(mock.getConfigCallCount == 0)
        #expect(mock.getConfigCallArgs == [])
        #expect(mock.getConfigHandler == nil)
        #expect(mock._environment == nil)
    }

    @Test("Package protocol mock reset works")
    func packageProtocolReset() {
        let mock = PackageDataServiceMock()

        mock.loadDataHandler = { @Sendable in nil }
        _ = mock.loadData()
        mock._isReady = true

        #expect(mock.loadDataCallCount == 1)

        mock.resetMock()

        #expect(mock.loadDataCallCount == 0)
        #expect(mock.loadDataCallArgs.isEmpty)
        #expect(mock.loadDataHandler == nil)
        #expect(mock._isReady == nil)
    }
}
