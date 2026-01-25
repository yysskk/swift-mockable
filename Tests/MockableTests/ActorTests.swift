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

    // MARK: - resetMock Tests for Actor Mocks

    @Test("Actor mock resetMock resets method call tracking")
    func actorMockResetMockResetsMethodTracking() async {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = UserProfileStoreMock()
        mock.updateProfileHandler = { _ in }
        mock.profileHandler = { _ in nil }
        mock.resetHandler = {}

        await mock.updateProfile("profile1", for: "key1")
        await mock.updateProfile("profile2", for: "key2")
        _ = await mock.profile(for: "key1")
        await mock.reset()

        #expect(mock.updateProfileCallCount == 2)
        #expect(mock.profileCallCount == 1)
        #expect(mock.resetCallCount == 1)

        mock.resetMock()

        #expect(mock.updateProfileCallCount == 0)
        #expect(mock.updateProfileCallArgs.isEmpty)
        #expect(mock.updateProfileHandler == nil)
        #expect(mock.profileCallCount == 0)
        #expect(mock.profileCallArgs.isEmpty)
        #expect(mock.profileHandler == nil)
        #expect(mock.resetCallCount == 0)
        #expect(mock.resetCallArgs.isEmpty)
        #expect(mock.resetHandler == nil)
    }

    @Test("Actor mock resetMock resets properties")
    func actorMockResetMockResetsProperties() async {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = UserProfileStoreMock()
        mock._profiles = ["key1": "profile1", "key2": "profile2"]

        let profiles = await mock.profiles
        #expect(profiles.count == 2)

        mock.resetMock()

        #expect(mock._profiles == nil)
    }

    @Test("Actor mock resetMock allows reuse")
    func actorMockResetMockAllowsReuse() async {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = UserProfileStoreMock()
        mock.updateProfileHandler = { _ in }

        await mock.updateProfile("first", for: "key")
        #expect(mock.updateProfileCallCount == 1)

        mock.resetMock()

        mock.updateProfileHandler = { _ in }
        await mock.updateProfile("second", for: "key")
        await mock.updateProfile("third", for: "key")

        #expect(mock.updateProfileCallCount == 2)
        #expect(mock.updateProfileCallArgs.count == 2)
        #expect(mock.updateProfileCallArgs[0].profile == "second")
        #expect(mock.updateProfileCallArgs[1].profile == "third")
    }

    @Test("Async actor mock resetMock resets async method tracking")
    func asyncActorMockResetMockResetsAsyncMethod() async throws {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = AsyncDataStoreMock()
        mock.saveHandler = { _ in }
        mock.loadHandler = { "data" }
        mock.deleteHandler = { _ in }

        try await mock.save("test")
        _ = try await mock.load()
        await mock.delete(id: 1)

        #expect(mock.saveCallCount == 1)
        #expect(mock.loadCallCount == 1)
        #expect(mock.deleteCallCount == 1)

        mock.resetMock()

        #expect(mock.saveCallCount == 0)
        #expect(mock.saveCallArgs == [])
        #expect(mock.saveHandler == nil)
        #expect(mock.loadCallCount == 0)
        #expect(mock.loadCallArgs.isEmpty)
        #expect(mock.loadHandler == nil)
        #expect(mock.deleteCallCount == 0)
        #expect(mock.deleteCallArgs.isEmpty)
        #expect(mock.deleteHandler == nil)
    }

    @Test("Actor config provider resetMock resets all properties")
    func actorConfigProviderResetMockResetsProperties() async {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = ActorConfigProviderMock()
        mock._apiKey = "secret"
        mock._timeout = 30
        mock._optionalEndpoint = "https://example.com"

        mock.resetMock()

        #expect(mock._apiKey == nil)
        #expect(mock._timeout == nil)
        #expect(mock._optionalEndpoint == nil)
    }

    @Test("Actor mock resetMock is nonisolated")
    func actorMockResetMockIsNonisolated() async {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = UserProfileStoreMock()
        mock.updateProfileHandler = { _ in }

        await mock.updateProfile("test", for: "key")

        // resetMock can be called without await because it's nonisolated
        mock.resetMock()

        #expect(mock.updateProfileCallCount == 0)
    }

    @Test("Actor mock resetMock is thread-safe with concurrent access")
    func actorMockResetMockIsThreadSafe() async {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) else { return }
        let mock = UserProfileStoreMock()
        mock.updateProfileHandler = { _ in }

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    await mock.updateProfile("profile\(i)", for: "key\(i)")
                }
            }
            for _ in 0..<10 {
                group.addTask {
                    mock.resetMock()
                }
            }
        }

        // Just verify no crashes occurred
        #expect(mock.updateProfileCallCount >= 0)
    }
}
