import Testing

import Mockable

@Suite("Initializer Requirement Tests")
struct InitializerRequirementTests {
    @Test("Init requirement records call count and arguments")
    func recordsInitializerCall() {
        let mock = ConfigurableServiceMock(configuration: "production")

        #expect(mock.initCallCount == 1)
        #expect(mock.initCallArgs == ["production"])
    }

    @Test("Mock satisfies an init requirement used through a generic constraint")
    func satisfiesGenericInitializerRequirement() {
        func make<Service: ConfigurableService>(_ type: Service.Type, configuration: String) -> Service {
            Service(configuration: configuration)
        }

        let mock = make(ConfigurableServiceMock.self, configuration: "generic")

        #expect(mock.initCallCount == 1)
        #expect(mock.initCallArgs == ["generic"])
    }

    @Test("Overloaded init requirements are tracked separately")
    func overloadedInitializersAreTrackedSeparately() {
        let byHost = MultiInitServiceMock(host: "example.com")
        #expect(byHost.initStringCallCount == 1)
        #expect(byHost.initStringIntCallCount == 0)
        #expect(byHost.initStringCallArgs == ["example.com"])

        let byHostAndPort = MultiInitServiceMock(host: "example.com", port: 8080)
        #expect(byHostAndPort.initStringIntCallCount == 1)
        #expect(byHostAndPort.initStringCallCount == 0)
        #expect(byHostAndPort.initStringIntCallArgs.count == 1)
        #expect(byHostAndPort.initStringIntCallArgs[0].host == "example.com")
        #expect(byHostAndPort.initStringIntCallArgs[0].port == 8080)
    }

    @Test("Throwing init requirement can be constructed and records the call")
    func throwingInitializerRecordsCall() throws {
        let mock = try ThrowingInitServiceMock(path: "/etc/config")

        #expect(mock.initCallCount == 1)
        #expect(mock.initCallArgs == ["/etc/config"])
    }

    @Test("Failable init requirement records the call")
    func failableInitializerRecordsCall() {
        let mock = FailableInitServiceMock(rawValue: "value")

        #expect(mock?.initCallCount == 1)
        #expect(mock?.initCallArgs == ["value"])
    }

    @Test("resetMock clears init tracking")
    func resetClearsInitializerTracking() {
        let mock = ConfigurableServiceMock(configuration: "value")
        #expect(mock.initCallCount == 1)

        mock.resetMock()

        #expect(mock.initCallCount == 0)
        #expect(mock.initCallArgs == [])
    }
}
