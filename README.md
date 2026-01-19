# swift-mockable

A Swift macro that generates mock classes from protocols for testing.

## Requirements

- Swift 6.2+
- macOS 10.15+ / iOS 13+ / tvOS 13+ / watchOS 6+

## Installation

### Swift Package Manager

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

Apply `@Mockable` to any protocol to generate a mock class:

```swift
import Mockable

@Mockable
protocol UserService {
    func fetchUser(id: Int) async throws -> User
    func saveUser(_ user: User) async throws
    var currentUser: User? { get }
    var isLoggedIn: Bool { get set }
}
```

This generates a `MockUserService` class with:

### Method Mocking

For each method, the mock provides:

- `<method>CallCount`: Number of times the method was called
- `<method>CallArgs`: Array of arguments from each call
- `<method>Handler`: Closure to define the mock behavior

```swift
let mock = MockUserService()

// Configure the handler
mock.fetchUserHandler = { id in
    User(id: id, name: "Test User")
}

// Use in tests
let user = try await mock.fetchUser(id: 42)

// Verify calls
#expect(mock.fetchUserCallCount == 1)
#expect(mock.fetchUserCallArgs.first == 42)
```

### Property Mocking

For get-only properties, use the backing storage:

```swift
mock._currentUser = User(id: 1, name: "Current")
print(mock.currentUser) // User(id: 1, name: "Current")
```

For get/set properties, assign directly:

```swift
mock.isLoggedIn = true
```

### Void Methods

Void methods don't require a handler to be set:

```swift
mock.saveUserHandler = { user in
    // Optional: perform assertions or side effects
}

try await mock.saveUser(user) // Works even without handler
```

### Methods with Return Values

Methods with return values require a handler, otherwise they will crash with `fatalError`:

```swift
// This will crash if handler is not set
mock.fetchUserHandler = { id in
    User(id: id, name: "Test")
}
```

## Generated Code Example

For the `UserService` protocol above, the following mock class is generated (wrapped in `#if DEBUG`):

```swift
#if DEBUG
public class MockUserService: UserService {
    // fetchUser
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

    // saveUser
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

    // currentUser (get-only)
    public var _currentUser: User?
    public var currentUser: User? {
        _currentUser
    }

    // isLoggedIn (get/set)
    public var isLoggedIn: Bool!
}
#endif
```

## License

MIT License
