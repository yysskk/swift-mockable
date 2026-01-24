import Foundation
import Testing

import Mockable

// MARK: - Test Protocols

@Mockable
protocol UserProfileStore: Actor {
    var profiles: [String: String] { get }
    func updateProfile(_ profile: String, for key: String)
    func profile(for key: String) -> String?
    func reset()
}

@Mockable
protocol AsyncDataStore: Actor {
    func save(_ data: String) async throws
    func load() async throws -> String
    func delete(id: Int) async
}

@Mockable
protocol ActorConfigProvider: Actor {
    var apiKey: String { get }
    var timeout: Int { get set }
    var optionalEndpoint: String? { get set }
}

// MARK: - Actor Integration Tests

@Suite("Actor Integration Tests")
struct ActorIntegrationTests {
    @Test("Actor mock can be instantiated")
    func actorMockCanBeInstantiated() {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = UserProfileStoreMock()
        let count = mock.updateProfileCallCount
        #expect(count == 0)
    }

    @Test("Actor mock conforms to Actor protocol")
    func actorMockConformsToActorProtocol() async {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        func useActor(_ actor: some Actor) async {}
        let mock = UserProfileStoreMock()
        await useActor(mock)
    }

    @Test("Actor mock conforms to protocol")
    func actorMockConformsToProtocol() async {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        func useStore(_ store: some UserProfileStore) async {
            await store.updateProfile("test", for: "key1")
        }

        let mock = UserProfileStoreMock()
        mock.updateProfileHandler = { _ in }

        await useStore(mock)

        let count = mock.updateProfileCallCount
        #expect(count == 1)
    }

    @Test("Actor mock void method tracking")
    func actorMockVoidMethodTracking() async {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = UserProfileStoreMock()
        mock.updateProfileHandler = { _ in }

        await mock.updateProfile("profile1", for: "key1")
        await mock.updateProfile("profile2", for: "key2")
        await mock.updateProfile("profile3", for: "key3")

        let count = mock.updateProfileCallCount
        let args = mock.updateProfileCallArgs

        #expect(count == 3)
        #expect(args.count == 3)
        #expect(args[0].profile == "profile1")
        #expect(args[0].key == "key1")
        #expect(args[1].profile == "profile2")
        #expect(args[1].key == "key2")
    }

    @Test("Actor mock return value method with handler")
    func actorMockReturnValueMethod() async {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = UserProfileStoreMock()
        mock.profileHandler = { key in
            key == "existing" ? "Found Profile" : nil
        }

        let result1 = await mock.profile(for: "existing")
        let result2 = await mock.profile(for: "missing")

        #expect(result1 == "Found Profile")
        #expect(result2 == nil)

        let count = mock.profileCallCount
        #expect(count == 2)
    }

    @Test("Actor mock reset method")
    func actorMockResetMethod() async {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = UserProfileStoreMock()
        mock.resetHandler = {}

        await mock.reset()
        await mock.reset()

        let count = mock.resetCallCount
        #expect(count == 2)
    }

    @Test("Actor mock get-only property")
    func actorMockGetOnlyProperty() async {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = UserProfileStoreMock()
        mock._profiles = ["key1": "profile1", "key2": "profile2"]

        let profiles = await mock.profiles
        #expect(profiles.count == 2)
        #expect(profiles["key1"] == "profile1")
    }

    @Test("Async actor mock can save data")
    func asyncActorMockSave() async throws {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = AsyncDataStoreMock()

        mock.saveHandler = { _ in }

        try await mock.save("data1")
        try await mock.save("data2")

        let count = mock.saveCallCount
        let args = mock.saveCallArgs

        #expect(count == 2)
        #expect(args == ["data1", "data2"])
    }

    @Test("Async actor mock can load data")
    func asyncActorMockLoad() async throws {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = AsyncDataStoreMock()
        mock.loadHandler = {
            "loaded data"
        }

        let result = try await mock.load()

        #expect(result == "loaded data")

        let count = mock.loadCallCount
        #expect(count == 1)
    }

    @Test("Async actor mock can throw errors")
    func asyncActorMockThrows() async {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = AsyncDataStoreMock()

        struct TestError: Error {}

        mock.saveHandler = { _ in
            throw TestError()
        }

        do {
            try await mock.save("data")
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(error is TestError)
        }

        let count = mock.saveCallCount
        #expect(count == 1)
    }

    @Test("Async actor mock delete method")
    func asyncActorMockDelete() async {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = AsyncDataStoreMock()
        mock.deleteHandler = { _ in }

        await mock.delete(id: 1)
        await mock.delete(id: 2)
        await mock.delete(id: 3)

        let count = mock.deleteCallCount
        let args = mock.deleteCallArgs

        #expect(count == 3)
        #expect(args == [1, 2, 3])
    }

    @Test("Actor config provider get-only property")
    func actorConfigProviderGetOnlyProperty() async {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = ActorConfigProviderMock()
        mock._apiKey = "secret-key"

        let apiKey = await mock.apiKey
        #expect(apiKey == "secret-key")
    }

    @Test("Actor config provider get-set property")
    func actorConfigProviderGetSetProperty() async {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = ActorConfigProviderMock()
        mock._timeout = 30

        let timeout = await mock.timeout
        #expect(timeout == 30)

        mock._timeout = 60
        let newTimeout = await mock.timeout
        #expect(newTimeout == 60)
    }

    @Test("Actor config provider optional property")
    func actorConfigProviderOptionalProperty() async {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = ActorConfigProviderMock()

        let initialValue = await mock.optionalEndpoint
        #expect(initialValue == nil)

        mock._optionalEndpoint = "https://api.example.com"
        let setValue = await mock.optionalEndpoint
        #expect(setValue == "https://api.example.com")

        mock._optionalEndpoint = nil
        let clearedValue = await mock.optionalEndpoint
        #expect(clearedValue == nil)
    }

    @Test("Actor mock can be used from multiple tasks")
    func actorMockConcurrentAccess() async {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = UserProfileStoreMock()
        mock.updateProfileHandler = { _ in }

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    await mock.updateProfile("profile\(i)", for: "key\(i)")
                }
            }
        }

        let count = mock.updateProfileCallCount
        let args = mock.updateProfileCallArgs

        #expect(count == 100)
        #expect(args.count == 100)
    }

    @Test("Actor mock is implicitly Sendable")
    func actorMockIsSendable() async {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = UserProfileStoreMock()
        mock.resetHandler = {}

        // Actors are implicitly Sendable
        func useSendable<T: Sendable>(_ value: T) -> T { value }
        let result = useSendable(mock)

        await result.reset()
        let count = mock.resetCallCount
        #expect(count == 1)
    }
}
