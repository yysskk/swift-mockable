# swift-mockable

`swift-mockable` provides a `@Mockable` macro that generates protocol mocks for tests.

- Generated mocks are emitted inside `#if DEBUG`.
- Generated names follow a predictable convention (`<name>CallCount`, `<name>CallArgs`, `<name>Handler`).
- `resetMock()` is generated to clear all tracking state.

## Installation

Add the package:

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

## Quick Start

```swift
import Mockable

@Mockable
protocol UserService {
    func fetchUser(id: Int) async throws -> User
    func saveUser(_ user: User) async throws
    var currentUser: User? { get }
    var isLoggedIn: Bool { get set }
}

let mock = UserServiceMock()

mock.fetchUserHandler = { id in
    User(id: id, name: "Test User")
}

mock._currentUser = User(id: 1, name: "Current")
mock.isLoggedIn = true

let user = try await mock.fetchUser(id: 42)

#expect(user.id == 42)
#expect(mock.fetchUserCallCount == 1)
#expect(mock.fetchUserCallArgs == [42])

mock.resetMock()
#expect(mock.fetchUserCallCount == 0)
```

## What Gets Generated

For each protocol requirement, `@Mockable` generates test-friendly members:

- Functions:
  - `<method>CallCount`
  - `<method>CallArgs`
  - `<method>Handler`
- Properties:
  - Backing storage for setup (for example `_<property>`)
  - Computed protocol-conforming property (`property`)
- Subscripts:
  - `subscript<suffix>CallCount`
  - `subscript<suffix>CallArgs`
  - `subscript<suffix>Handler`
  - `subscript<suffix>SetHandler` for get/set subscripts
- Utility:
  - `resetMock()`

## Supported Features

- Access-level-aware generation (including `private` / `fileprivate` edge cases)
- Sync / `async` / `throws` methods
- Variadic parameters (captured as arrays)
- `inout` parameters with write-back support
- Generic methods (generic parameters are type-erased to `Any` in storage/handlers)
- Overloaded methods (unique suffixes are added to generated names when needed)
- Associated types (generated as `typealias`, using default type when available, otherwise `Any`)
- Static methods and static properties
- Get-only / get-set / optional properties
- Get-only / get-set subscripts
- `#if` / `#elseif` / `#else` conditional compilation inside protocols
- Protocol inheritance (child mock inherits from first parent mock when applicable)
- `Sendable` protocol support (`@unchecked Sendable` mock generation)
- `Actor` protocol support (actor mock generation with nonisolated helper members)

## Behavioral Notes

- Return-value methods and get-only subscripts `fatalError` if their handler is not set.
- Void-return methods and subscript setters are no-op when handler is `nil`.
- `resetMock()` clears handlers, call counts, call arguments, and backing properties.
- For inherited protocols, `resetMock()` calls `super.resetMock()` before resetting child members.

## Diagnostics and Limitations

- `@Mockable` can only be applied to protocols.
- `@Mockable` does not accept arguments.
- Unsupported protocol members (for example `init`) emit compile-time diagnostics.
- Static/class subscripts are not supported.
- For protocols with multiple parent protocols, the first parent is used as the mock superclass.

## Documentation

- [Docs index](docs/README.md)
- [Advanced usage and naming rules](docs/advanced-usage.md)

## Requirements

- Swift 5.9, 5.10, and 6.2+
- macOS 10.15+ / iOS 13+ / tvOS 13+ / watchOS 6+
- `MockableLock` lock strategy:
  - iOS 18.0+ / macOS 15.0+ / tvOS 18.0+ / watchOS 11.0+: prefers `Mutex` (`Synchronization`)
  - Older OS versions: falls back to `LegacyLock` (`NSLock`-based)

## License

MIT
