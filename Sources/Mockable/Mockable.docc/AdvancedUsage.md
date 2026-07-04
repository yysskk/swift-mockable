# Advanced Usage

Naming conventions, edge-case behavior, and constraints of `@Mockable`.

## Naming Conventions

### Methods

For a non-overloaded method `fetch`, generated members are:

- `fetchCallCount`
- `fetchCallArgs`
- `fetchHandler`

For overloaded methods, a suffix is appended:

1. Start with sanitized parameter type names.
2. If that still collides, append return type (if non-`Void`), `Async` (for `async`), and `Throwing` (for `throws`).

Example:

```swift
func get(url: URL) async -> String
func get(url: URL) async throws -> Data
```

Generates distinct handlers like `getURLStringAsyncHandler` and `getURLDataAsyncThrowingHandler`.

### Subscripts

Subscript-generated names use `subscript<suffix>...`, where the suffix is based on parameter types.

```swift
subscript(index: Int) -> String { get }
```

Generates `subscriptIntCallCount`, `subscriptIntCallArgs`, and `subscriptIntHandler`. Get/set subscripts also generate `subscript<suffix>SetHandler`.

## Generic and Associated Types

### Generic Methods

Generic type parameters are type-erased to `Any` in `CallArgs` storage and handlers. Generated method implementations cast generic returns back to the requested type.

### Associated Types

Each associated type generates a `typealias` in the mock. If the protocol provides a default type, that type is used; otherwise `Any` is used.

```swift
associatedtype Value = Int   // -> typealias Value = Int
associatedtype Value         // -> typealias Value = Any
```

## `@autoclosure` Parameters

`@autoclosure` arguments are evaluated exactly once per call, before the call is recorded. `CallArgs` and handlers observe the evaluated value, not the closure:

```swift
func log(_ message: @autoclosure () -> String)
// generates:
// var logCallArgs: [String] = []
// var logHandler: (@Sendable (String) -> Void)? = nil
```

The argument is evaluated even when no handler is set. If evaluating a throwing autoclosure throws, the error propagates before the call is recorded. An autoclosure's own effects must be covered by the requirement (`throws`/`async`); effectful autoclosures are not supported in subscript requirements.

## Non-Escaping Closure Parameters

A non-escaping closure parameter cannot be stored, so it is excluded from `CallArgs`. The call is still counted, and the closure is still forwarded to the handler:

```swift
func run(label: String, _ body: () -> Void)
// generates:
// var runCallArgs: [String] = []                         // only the storable `label`
// var runHandler: (@Sendable (String, () -> Void) -> Void)? = nil
```

Escaping (`@escaping`), optional, and variadic closures are storable and remain in `CallArgs` as before.

## `inout` and Variadic Parameters

### Variadic

Variadic parameters are tracked as arrays in `CallArgs`.

### `inout`

`CallArgs` stores the input snapshot before mutation. Handler return shapes:

- Single `inout`, no return value: handler returns the updated value.
- Multiple `inout`, no return value: handler returns a tuple with updated values.
- `inout` + return value: handler returns `(returnValue: ..., inoutArgs: ...)`.

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

## Effectful Read-Only Properties

Read-only properties with `get async`, `get throws`, or `get async throws` are mocked with a handler and a call counter instead of `_name` backing storage:

```swift
var token: String { get async throws }
// generates:
// var tokenCallCount: Int = 0
// var tokenHandler: (@Sendable () async throws -> String)? = nil
```

Configure it in tests like a method handler (`mock.tokenHandler = { "secret" }` or `{ throw AuthError.expired }`). If the handler is unset, the same defaults as methods apply (Optionals return `nil`, collections return empty values, other types call `fatalError`).

Read-only subscripts with the same effects (`subscript(key: K) -> V { get async throws }`) work identically — the generated `subscript<suffix>Handler` gains the matching `async`/`throws` effects.

## `Sendable` and `Actor` Mocks

### `Sendable`

If a protocol inherits from `Sendable`, generated mocks conform to `@unchecked Sendable` and store mutable state behind ``MockableLock``.

### `Actor`

If a protocol inherits from `Actor`, the generated mock type is an actor. Helper members (call counters, argument collections, handlers, backing properties, `resetMock()`) are generated as `nonisolated` for test ergonomics.

## Static Members

Static methods and properties are lock-backed through a shared static storage. `resetMock()` also resets static generated members.

## Inheritance and `resetMock()`

If a protocol inherits from another protocol and a parent mock exists, the child mock inherits from the parent mock. Child `resetMock()` calls `super.resetMock()` first.

For multiple parent protocols, the first parent is used as the superclass target.

## Conditional Compilation

Protocol members inside `#if` / `#elseif` / `#else` are preserved in generated mocks. `resetMock()` includes matching conditional branches so reset behavior stays aligned with active compilation conditions.

## Diagnostics

Compilation errors are emitted when:

- `@Mockable` is applied to non-protocol declarations.
- Unsupported members are present (for example initializers).
- Arguments are passed to `@Mockable` (it accepts none).

## Current Constraints

- Static/class subscripts are not supported.
- Return-value methods and get-only subscript getters trigger `fatalError` when the handler is unset, unless the return type has a natural empty value: Optionals return `nil`, arrays and sets return an empty collection, and dictionaries return an empty dictionary.
