import Testing

import Mockable

@Suite("Initializer Requirement Tests")
struct InitializerRequirementTests {
    @Test("Init requirement records call count and arguments")
    func recordsInitializerCall() {
        let mock = ConfigurableServiceMock(configuration: "production")

        #expect(mock.initCallCount == 1)
        #expect(mock.initCallArguments == ["production"])
    }

    @Test("Mock satisfies an init requirement used through a generic constraint")
    func satisfiesGenericInitializerRequirement() {
        func make<Service: ConfigurableService>(_ type: Service.Type, configuration: String) -> Service {
            Service(configuration: configuration)
        }

        let mock = make(ConfigurableServiceMock.self, configuration: "generic")

        #expect(mock.initCallCount == 1)
        #expect(mock.initCallArguments == ["generic"])
    }

    @Test("Overloaded init requirements are tracked separately")
    func overloadedInitializersAreTrackedSeparately() {
        let byHost = MultiInitServiceMock(host: "example.com")
        #expect(byHost.initHostCallCount == 1)
        #expect(byHost.initHostPortCallCount == 0)
        #expect(byHost.initHostCallArguments == ["example.com"])

        let byHostAndPort = MultiInitServiceMock(host: "example.com", port: 8080)
        #expect(byHostAndPort.initHostPortCallCount == 1)
        #expect(byHostAndPort.initHostCallCount == 0)
        #expect(byHostAndPort.initHostPortCallArguments.count == 1)
        #expect(byHostAndPort.initHostPortCallArguments[0].host == "example.com")
        #expect(byHostAndPort.initHostPortCallArguments[0].port == 8080)
    }

    @Test("Throwing init requirement can be constructed and records the call")
    func throwingInitializerRecordsCall() throws {
        let mock = try ThrowingInitServiceMock(path: "/etc/config")

        #expect(mock.initCallCount == 1)
        #expect(mock.initCallArguments == ["/etc/config"])
    }

    @Test("Failable init requirement records the call")
    func failableInitializerRecordsCall() {
        let mock = FailableInitServiceMock(rawValue: "value")

        #expect(mock?.initCallCount == 1)
        #expect(mock?.initCallArguments == ["value"])
    }

    @Test("resetMock clears init tracking")
    func resetClearsInitializerTracking() {
        let mock = ConfigurableServiceMock(configuration: "value")
        #expect(mock.initCallCount == 1)

        mock.resetMock()

        #expect(mock.initCallCount == 0)
        #expect(mock.initCallArguments == [])
    }

    @Test("Sendable protocol init requirement is recorded behind the lock")
    func sendableInitializerRecordsCall() {
        let mock = SendableInitServiceMock(configuration: "prod")

        #expect(mock.initCallCount == 1)
        #expect(mock.initCallArguments == ["prod"])

        mock.resetMock()
        #expect(mock.initCallCount == 0)
        #expect(mock.initCallArguments == [])
    }

    @Test("Actor protocol init requirement is recorded through nonisolated tracking")
    func actorInitializerRecordsCall() {
        let mock = ActorInitServiceMock(identifier: 7)

        #expect(mock.initCallCount == 1)
        #expect(mock.initCallArguments == [7])
    }

    @Test("Child mock inherits the parent's init requirement and its recording")
    func childMockInheritsParentInitializer() {
        let mock = InheritingInitServiceMock(token: "session")

        #expect(mock.initCallCount == 1)
        #expect(mock.initCallArguments == ["session"])
    }

    @Test("Child mock without an init requirement is constructible via the inherited init")
    func childMockIsConstructibleThroughInheritedInit() {
        let mock = PublicChildServiceMock()
        mock.childValueHandler = { 42 }

        #expect(mock.childValue() == 42)
    }
}
