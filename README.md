# swift-mockable

A Swift Macro that generates mock classes from protocols for testing.

## Installation

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yysskk/swift-mockable.git", from: "0.1.0")
]
```

Then add `Mockable` to your target dependencies:

```swift
.target(
    name: "YourTarget",
    dependencies: ["Mockable"]
)
```

## Features

- Generates mock classes wrapped in `#if DEBUG`
- Respects protocol access levels (`public`, `package`, `internal`)
- Call count tracking (`<method>CallCount`)
- Call arguments recording (`<method>CallArgs`)
- Configurable handlers with `@Sendable` support (`<method>Handler`)
- Supports `async` and `throws` methods
- Supports get-only and get/set properties
- Supports optional properties
- Supports generic methods (with type erasure to `Any`)
- Supports `Sendable` protocols with thread-safe mock generation
- Supports `Actor` protocols with actor mock generation
- Backward compatible: iOS 18+ uses `Mutex`, iOS 17 and earlier uses `LegacyLock`
- `legacyLock: true` option to force `LegacyLock` for projects supporting iOS 17 or earlier
- Supports subscript declarations (get-only and get-set)
- `resetMock()` method to reset all tracking state for test reuse

## Usage

```swift
import Mockable

@Mockable
protocol UserService {
    func fetchUser(id: Int) async throws -> User
    func saveUser(_ user: User) async throws
    var currentUser: User? { get }
    var isLoggedIn: Bool { get set }
}

// In tests
let mock = UserServiceMock()

// Configure handlers
mock.fetchUserHandler = { id in
    User(id: id, name: "Test User")
}

// Set properties
mock._currentUser = User(id: 1, name: "Current")
mock.isLoggedIn = true

// Use in tests
let user = try await mock.fetchUser(id: 42)

// Verify calls
#expect(mock.fetchUserCallCount == 1)
#expect(mock.fetchUserCallArgs.first == 42)

// Reset mock for reuse in another test case
mock.resetMock()
#expect(mock.fetchUserCallCount == 0)
```

### Void methods

Void methods don't require a handler to be set:

```swift
mock.saveUserHandler = { user in
    // Optional: perform assertions or side effects
}

try await mock.saveUser(user) // Works even without handler
```

### Methods with return values

Methods with return values require a handler, otherwise they will crash with `fatalError`:

```swift
// This will crash if handler is not set
mock.fetchUserHandler = { id in
    User(id: id, name: "Test")
}
```

### Generic methods

Generic methods are supported with type erasure. Parameters and return types containing generic type parameters are erased to `Any`:

```swift
@Mockable
protocol Storage {
    func get<T>(_ key: UserDefaultsKey<T>) -> T
    func set<T>(_ value: T, forKey key: UserDefaultsKey<T>)
}

// In tests
let mock = StorageMock()

mock.getHandler = { key in
    return "stored value"  // Returns Any, cast to T at call site
}

mock.setHandler = { value, key in
    // value and key are Any
}

let result: String = mock.get(UserDefaultsKey<String>("name"))
```

**Note:** For non-generic methods with concrete generic types (e.g., `UserDefaultsKey<Int>`), full type information is preserved:

```swift
@Mockable
protocol UserDefaultsClient {
    func integer(forKey key: UserDefaultsKey<Int>) -> Int
}

// Generated mock preserves the concrete type
// mock.integerCallArgs: [UserDefaultsKey<Int>]
```

### Sendable protocols

Protocols that inherit from `Sendable` or have the `@Sendable` attribute generate thread-safe mocks using `Mutex`:

```swift
@Mockable
protocol KeychainClient: Sendable {
    func save(_ data: Data, forKey key: String) throws
    func load(forKey key: String) throws -> Data?
}

// Generated mock is thread-safe and can be used from multiple tasks
let mock = KeychainClientMock()
mock.loadHandler = { @Sendable key in
    "test data".data(using: .utf8)
}

// Safe to use concurrently
await withTaskGroup(of: Void.self) { group in
    for _ in 0..<100 {
        group.addTask {
            _ = try? mock.load(forKey: "key")
        }
    }
}

#expect(mock.loadCallCount == 100)
```

**Platform Support:** Sendable mocks automatically use the appropriate lock implementation:
- **iOS 18.0+ / macOS 15.0+ / tvOS 18.0+ / watchOS 11.0+**: Uses `Mutex` from the `Synchronization` module (generated with `@available` attribute)
- **iOS 17 and earlier**: Uses `LegacyLock` (NSLock-based) for backward compatibility

The generated code uses `#if canImport(Synchronization)` to automatically select the correct implementation at compile time.

#### Force LegacyLock for iOS 17 support

If your project needs to support iOS 17 or earlier while using `Sendable` protocols, you can force the use of `LegacyLock` by passing `legacyLock: true`:

```swift
@Mockable(legacyLock: true)
protocol KeychainClient: Sendable {
    func save(_ data: Data, forKey key: String) throws
    func load(forKey key: String) throws -> Data?
}
```

This generates a mock that uses `LegacyLock` without any `#if canImport(Synchronization)` conditional compilation or `@available` attributes, ensuring compatibility with iOS 17 and earlier.

### Actor protocols

Protocols that inherit from `Actor` generate actor mocks with thread-safe access using `Mutex`:

```swift
@Mockable
protocol UserProfileStore: Actor {
    var profiles: [String: String] { get }
    func updateProfile(_ profile: String, for key: String)
    func profile(for key: String) -> String?
    func reset()
}

// Generated mock is an actor and can be used safely from multiple tasks
let mock = UserProfileStoreMock()
mock._profiles = ["key1": "profile1"]
mock.profileHandler = { key in
    key == "existing" ? "Found" : nil
}

// Access actor properties and methods
let profiles = await mock.profiles
let result = await mock.profile(for: "existing")

// Verify calls
#expect(mock.profileCallCount == 1)
```

Actor mocks support:
- Async methods with `async throws`
- Get-only and get-set properties
- Concurrent access from multiple tasks
- Implicit `Sendable` conformance (all actors are Sendable)
- `nonisolated` helper properties (`CallCount`, `CallArgs`, `Handler`) for easy test verification without `await`
- `nonisolated` backing properties (`_propertyName`) for easy test setup without `await`
- `nonisolated func resetMock()` for easy mock reset without `await`

**Platform Support:** Actor mocks automatically use the appropriate lock implementation:
- **iOS 18.0+ / macOS 15.0+ / tvOS 18.0+ / watchOS 11.0+**: Uses `Mutex` from the `Synchronization` module (generated with `@available` attribute)
- **iOS 17 and earlier**: Uses `LegacyLock` (NSLock-based) for backward compatibility

The generated code uses `#if canImport(Synchronization)` to automatically select the correct implementation at compile time.

#### Force LegacyLock for iOS 17 support

If your project needs to support iOS 17 or earlier while using `Actor` protocols, you can force the use of `LegacyLock` by passing `legacyLock: true`:

```swift
@Mockable(legacyLock: true)
protocol UserProfileStore: Actor {
    var profiles: [String: String] { get }
    func updateProfile(_ profile: String, for key: String)
}
```

This generates an actor mock that uses `LegacyLock` without any `#if canImport(Synchronization)` conditional compilation or `@available` attributes, ensuring compatibility with iOS 17 and earlier.

## Generated Code Example

For the `UserService` protocol above (which is `internal` by default), the following mock class is generated:

```swift
#if DEBUG
class UserServiceMock: UserService {
    var fetchUserCallCount: Int = 0
    var fetchUserCallArgs: [Int] = []
    var fetchUserHandler: (@Sendable (Int) async throws -> User)?

    func fetchUser(id: Int) async throws -> User {
        fetchUserCallCount += 1
        fetchUserCallArgs.append(id)
        guard let handler = fetchUserHandler else {
            fatalError("\(Self.self).fetchUserHandler is not set")
        }
        return try await handler(id)
    }

    var saveUserCallCount: Int = 0
    var saveUserCallArgs: [User] = []
    var saveUserHandler: (@Sendable (User) async throws -> Void)?

    func saveUser(_ user: User) async throws {
        saveUserCallCount += 1
        saveUserCallArgs.append(user)
        if let handler = saveUserHandler {
            try await handler(user)
        }
    }

    var _currentUser: User?
    var currentUser: User? {
        _currentUser
    }

    var _isLoggedIn: Bool?
    var isLoggedIn: Bool {
        get { _isLoggedIn! }
        set { _isLoggedIn = newValue }
    }

    func resetMock() {
        fetchUserCallCount = 0
        fetchUserCallArgs = []
        fetchUserHandler = nil
        saveUserCallCount = 0
        saveUserCallArgs = []
        saveUserHandler = nil
        _currentUser = nil
        _isLoggedIn = nil
    }
}
#endif
```

**Note:** If the protocol were declared as `public protocol UserService`, all generated members would have `public` access modifiers.

## Requirements

- Swift 5.9, 5.10, and 6.2+ are supported
- macOS 10.15+ / iOS 13+ / tvOS 13+ / watchOS 6+
- `Sendable` and `Actor` protocol mocks work on all supported platforms (iOS 13+, etc.)
  - iOS 18.0+ / macOS 15.0+: Uses `Mutex` for optimal performance
  - iOS 17 and earlier: Uses `LegacyLock` (NSLock-based) for compatibility

## License

MIT
