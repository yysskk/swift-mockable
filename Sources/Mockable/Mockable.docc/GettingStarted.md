# Getting Started

Add `@Mockable` to a protocol and start writing tests with generated mocks.

## Installation

Add the package dependency:

```swift
dependencies: [
    .package(url: "https://github.com/yysskk/swift-mockable.git", from: "0.1.0")
]
```

Add `Mockable` to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: ["Mockable"]
)
```

## Basic Usage

Apply the ``Mockable()`` macro to a protocol:

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

This generates a `UserServiceMock` class with test-friendly members.

## Using the Mock

```swift
let mock = UserServiceMock()

// Configure handlers
mock.fetchUserHandler = { id in
    User(id: id, name: "Test User")
}

// Set properties
mock._currentUser = User(id: 1, name: "Current")
mock.isLoggedIn = true

// Call methods
let user = try await mock.fetchUser(id: 42)

// Verify
#expect(user.id == 42)
#expect(mock.fetchUserCallCount == 1)
#expect(mock.fetchUserCallArgs == [42])

// Reset
mock.resetMock()
#expect(mock.fetchUserCallCount == 0)
```

## What Gets Generated

For each protocol requirement, `@Mockable` generates:

- **Functions**:
  - `<method>CallCount` -- number of calls
  - `<method>CallArgs` -- array of captured arguments
  - `<method>Handler` -- configurable closure
- **Properties**:
  - `_<property>` -- backing storage for get-only properties
  - `<property>` -- computed property for get/set properties
- **Subscripts**:
  - `subscript<suffix>CallCount`
  - `subscript<suffix>CallArgs`
  - `subscript<suffix>Handler`
  - `subscript<suffix>SetHandler` for get/set subscripts
- **Utility**:
  - `resetMock()` -- clears all tracking state

## Behavioral Notes

- Return-value methods and get-only subscripts call `fatalError` if their handler is not set.
- Void-return methods and subscript setters are no-ops when handler is `nil`.
- `resetMock()` clears handlers, call counts, call arguments, and backing properties.
- For inherited protocols, `resetMock()` calls `super.resetMock()` before resetting child members.
