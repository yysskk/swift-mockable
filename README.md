# swift-mockable

[![Test](https://github.com/yysskk/swift-mockable/actions/workflows/test.yml/badge.svg)](https://github.com/yysskk/swift-mockable/actions/workflows/test.yml)
[![Release](https://img.shields.io/github/v/release/yysskk/swift-mockable)](https://github.com/yysskk/swift-mockable/releases)
[![Swift](https://img.shields.io/badge/Swift-5.9%20%7C%205.10%20%7C%206.2-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-macOS%20%7C%20iOS%20%7C%20tvOS%20%7C%20watchOS%20%7C%20visionOS-blue.svg)](https://developer.apple.com)
[![License](https://img.shields.io/github/license/yysskk/swift-mockable)](LICENSE)

`swift-mockable` provides a `@Mockable` macro that generates protocol mocks for tests.

- Generated mocks are emitted inside `#if DEBUG`.
- Generated names follow a predictable convention (`<name>CallCount`, `<name>CallArgs`, `<name>Handler`).
- `resetMock()` is generated to clear all tracking state.

## Installation

Add the package:

```swift
dependencies: [
    .package(url: "https://github.com/yysskk/swift-mockable.git", from: "1.9.1")
]
```

Add `Mockable` to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: ["Mockable"]
)
```

> [!NOTE]
> The first time you build a target that uses `@Mockable`, Xcode shows a
> "trust macro" prompt. Choose **Trust & Enable** to allow the macro to run.
> On the command line, `swift build` runs macros without prompting.

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
- Initializers:
  - `initCallCount`
  - `initCallArgs`
  - (overloaded `init`s add a parameter-type suffix, e.g. `initStringCallCount`)
- Utility:
  - `resetMock()`

## Handlers

A handler for a member with two or more parameters takes individual parameters, so it
can be written as `{ a, b in ... }` (no tuple destructuring needed):

```swift
@Mockable
protocol Calculator {
    func add(a: Int, b: Int) -> Int
}

// var addHandler: (@Sendable (Int, Int) -> Int)? = nil
mock.addHandler = { a, b in a + b }
```

Notes:

- This applies to methods and subscripts alike (subscript getter `(Int, Int) -> V`, setter `(Int, Int, V) -> Void`).
- Zero- and single-parameter members pass their argument directly.
- `<name>CallArgs` is a labeled tuple array (e.g. `[(a: Int, b: Int)]`) — the call history keeps parameter labels even though the handler takes individual parameters.

## Supported Features

- Access-level-aware generation (including `private` / `fileprivate` edge cases)
- Sync / `async` / `throws` / `rethrows` methods
- Typed throws (`throws(MyError)`, SE-0413) on methods, properties, and subscripts
- Variadic parameters (captured as arrays)
- `@autoclosure` parameters (evaluated once per call; handlers and `CallArgs` receive the evaluated value)
- Non-escaping closure parameters (forwarded to the handler; excluded from `CallArgs`)
- `inout` parameters with write-back support
- Generic methods (generic parameters are type-erased to `Any` in storage/handlers)
- Overloaded methods (unique suffixes are added to generated names when needed)
- Initializer requirements (`init(...)`) generated as recording `required init` witnesses (`Sendable`/`actor` mocks record behind the lock)
- Associated types (generated as `typealias`, using default type when available, otherwise `Any`)
- Static methods and static properties
- Get-only / get-set / optional properties
- Effectful read-only properties (`get async`, `get throws`, `get async throws`) mocked with handlers
- Get-only / get-set subscripts (including effectful `get async` / `get throws` subscripts)
- `#if` / `#elseif` / `#else` conditional compilation inside protocols
- Protocol inheritance (child mock inherits from first parent mock when applicable)
- `Sendable` protocol support (`@unchecked Sendable` mock generation)
- `Actor` protocol support (actor mock generation with nonisolated helper members)

## Behavioral Notes

- Return-value methods and get-only subscripts return a default when their handler is not set if the return type has one: Optionals return `nil`, arrays and sets return an empty collection, and dictionaries return an empty dictionary. Any other return type calls `fatalError`.
- Properties with effectful getters (`get async`/`get throws`) generate `<name>CallCount` and `<name>Handler` instead of `_<name>` backing storage; the same unset-handler defaults apply.
- Void-return methods and subscript setters are no-op when handler is `nil`.
- `@autoclosure` arguments are evaluated exactly once per call (even when no handler is set); if evaluating a throwing autoclosure throws, the error propagates before the call is recorded.
- Non-escaping closure arguments are forwarded to the handler but excluded from `CallArgs` (a non-escaping value cannot be stored); the call is still counted.
- `rethrows` methods generate a non-throwing handler that receives the throwing closure arguments (a stored handler cannot satisfy `rethrows` on its own). The handler decides whether to invoke those closures; the mock itself does not re-throw their errors.
- Typed throws (`throws(MyError)`) keeps the `throws(MyError)` signature and generates a plain untyped-throwing handler; the body re-throws the handler's error as the declared type. Configure the handler normally (`mock.loadHandler = { id in throw MyError() }`). If the handler throws a different error type, the mock traps.
- `resetMock()` clears handlers, call counts, call arguments, and backing properties.
- For inherited protocols, `resetMock()` calls `super.resetMock()` before resetting child members.

## Diagnostics and Limitations

- `@Mockable` can only be applied to protocols.
- `@Mockable` does not accept arguments.
- Unsupported protocol members (for example a `static subscript`) emit compile-time diagnostics.
- `init` requirements are supported for standalone protocols, including `Sendable` and `actor` mocks; they are not yet supported for inheriting protocols, which emit a diagnostic.
- Static/class subscripts are not supported.
- For protocols with multiple parent protocols, the first parent is used as the mock superclass.

## Troubleshooting

- **The `<Protocol>Mock` type can't be found.** The generated mock lives inside
  `#if DEBUG`, so it only exists in debug builds. Reference it from test targets
  or debug configurations.
- **"Macro expansion" / trust prompt in Xcode.** Choose **Trust & Enable** the
  first time you build a target that uses `@Mockable` (see the note in
  [Installation](#installation)).
- **A handler is required.** A return-value method or get-only subscript with an
  unset handler calls `fatalError`, unless the return type has a natural empty
  value (see [Behavioral Notes](#behavioral-notes)). Set the corresponding
  `<name>Handler` in your test setup.
- **Overloaded calls need a type annotation.** For methods overloaded only by
  return type, annotate the result (e.g. `let value: String = mock.get(...)`) so
  Swift selects the right overload.

## Documentation

- [Docs index](docs/README.md)
- [Advanced usage and naming rules](docs/advanced-usage.md)
- [Changelog](CHANGELOG.md)
- [Contributing](CONTRIBUTING.md)

## Requirements

- Swift 5.9, 5.10, and 6.2+
- macOS 10.15+ / iOS 13+ / tvOS 13+ / watchOS 6+ / visionOS 1+
- `MockableLock` lock strategy:
  - iOS 18.0+ / macOS 15.0+ / tvOS 18.0+ / watchOS 11.0+ / visionOS 2.0+: prefers `Mutex` (`Synchronization`)
  - Older OS versions: falls back to `LegacyLock` (`NSLock`-based)

## License

MIT
