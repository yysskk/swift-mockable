# Advanced Usage

This guide explains generated naming, edge-case behavior, and constraints of `@Mockable`.

## Naming Conventions

### Methods

For a non-overloaded method `fetch`, generated members are:

- `fetchCallCount`
- `fetchCallArgs`
- `fetchHandler`

For overloaded methods, a suffix is appended:

1. Start with sanitized parameter type names.
2. If that still collides, append:
   - return type (if non-`Void`)
   - `Async` (for `async`)
   - `Throwing` (for `throws`)

Example:

```swift
func get(url: URL) async -> String
func get(url: URL) async throws -> Data
```

Generates distinct handlers like:

- `getURLStringAsyncHandler`
- `getURLDataAsyncThrowingHandler`

### Subscripts

Subscript-generated names use `subscript<suffix>...`.
The suffix is based on subscript parameter types.

Example:

```swift
subscript(index: Int) -> String { get }
```

Generates:

- `subscriptIntCallCount`
- `subscriptIntCallArgs`
- `subscriptIntHandler`

Get/set subscripts also generate `subscript<suffix>SetHandler`.

## Generic and Associated Types

### Generic Methods

When method signatures contain generic type parameters:

- `CallArgs` storage uses type erasure (`Any`) where needed.
- Handler parameter/return types are also erased where needed.
- Generated method implementations cast generic returns back to the requested type.

This keeps generated mocks concrete while preserving call tracking.

### Associated Types

Each associated type generates a `typealias` in the mock:

- If the protocol provides a default associated type, that type is used.
- Otherwise, `Any` is used.

Example:

```swift
associatedtype Value = Int
```

Generates:

```swift
typealias Value = Int
```

Without default:

```swift
associatedtype Value
```

Generates:

```swift
typealias Value = Any
```

## `inout` and Variadic Parameters

### Variadic

Variadic parameters are tracked as arrays in `CallArgs`.

### `inout`

`CallArgs` stores the input snapshot before mutation.

For handlers:

- Single `inout`, no return value:
  - handler returns the updated value
- Multiple `inout`, no return value:
  - handler returns a tuple with updated values
- `inout` + return value:
  - handler returns `(returnValue: ..., inoutArgs: ...)`

Example:

```swift
func removeFirst(_ array: inout [String]) -> String
```

Expected handler shape:

```swift
mock.removeFirstHandler = { array in
    let first = array.first!
    return (returnValue: first, inoutArgs: Array(array.dropFirst()))
}
```

## `Sendable` and `Actor` Mocks

### `Sendable`

If a protocol inherits from `Sendable` (or uses `@Sendable` at protocol level), generated mocks:

- conform to `@unchecked Sendable`
- store mutable state behind `MockableLock`

### `Actor`

If a protocol inherits from `Actor`, generated mock type is an actor.

For test ergonomics, helper members are generated as `nonisolated` where possible, including:

- call counters
- call argument collections
- handlers
- backing properties (for setup)
- `resetMock()`

## Static Members

Static methods/properties are always lock-backed through a shared static storage.

`resetMock()` also resets static generated members.

## Inheritance and `resetMock()`

If a protocol inherits from another protocol and a parent mock exists:

- child mock inherits from `<Parent>Mock`
- child `resetMock()` calls `super.resetMock()` first

For multiple parent protocols, the first parent is used as the superclass target.

## Conditional Compilation

Protocol members inside `#if` / `#elseif` / `#else` are preserved in generated mocks.

`resetMock()` includes matching conditional branches so reset behavior stays aligned with active compilation conditions.

## Diagnostics

Compilation errors are emitted when:

- `@Mockable` is applied to non-protocol declarations
- unsupported members are present (for example initializers)
- arguments are passed to `@Mockable` (it accepts none)

## Current Constraints

- Static/class subscripts are not supported.
- Return-value methods and get-only subscript getters require handler setup; missing handlers trigger `fatalError`.
