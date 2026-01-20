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

## Features

- Generates mock classes wrapped in `#if DEBUG`
- Call count tracking (`<method>CallCount`)
- Call arguments recording (`<method>CallArgs`)
- Configurable handlers with `@Sendable` support (`<method>Handler`)
- Supports `async` and `throws` methods
- Supports get-only and get/set properties
- Supports optional properties

## Generated Code Example

For the `UserService` protocol above, the following mock class is generated:

```swift
#if DEBUG
public class UserServiceMock: UserService {
    public var fetchUserCallCount: Int = 0
    public var fetchUserCallArgs: [Int] = []
    public var fetchUserHandler: (@Sendable (Int) async throws -> User)?

    public func fetchUser(id: Int) async throws -> User {
        fetchUserCallCount += 1
        fetchUserCallArgs.append(id)
        guard let handler = fetchUserHandler else {
            fatalError("\(Self.self).fetchUserHandler is not set")
        }
        return try await handler(id)
    }

    public var saveUserCallCount: Int = 0
    public var saveUserCallArgs: [User] = []
    public var saveUserHandler: (@Sendable (User) async throws -> Void)?

    public func saveUser(_ user: User) async throws {
        saveUserCallCount += 1
        saveUserCallArgs.append(user)
        if let handler = saveUserHandler {
            try await handler(user)
        }
    }

    public var _currentUser: User?
    public var currentUser: User? {
        _currentUser
    }

    public var isLoggedIn: Bool!
}
#endif
```

## Requirements

- Swift 6.2+
- macOS 10.15+ / iOS 13+ / tvOS 13+ / watchOS 6+

## License

MIT
