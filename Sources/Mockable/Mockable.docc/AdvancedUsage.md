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

### Initializers

A sole `init` requirement uses the identifier `init` (`initCallCount`, `initCallArgs`). Overloaded initializers append a parameter-type suffix, matching the method scheme (`initStringCallCount`, `initStringIntCallCount`).

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

## `rethrows` Methods

A stored handler cannot satisfy a `rethrows` requirement on its own, so the mock keeps the `rethrows` signature but generates a **non-throwing** handler that receives the throwing closure arguments:

```swift
func run(_ body: () throws -> Void) rethrows
// generates: var runHandler: (@Sendable (() throws -> Void) -> Void)? = nil
```

The handler decides whether to invoke those closures; because it is non-throwing, the mock does not itself re-throw their errors — verify behavior through the handler and the call count.

## Typed Throws (SE-0413)

Typed throws (`throws(MyError)`) on methods, effectful properties, and effectful subscripts is supported. The mock keeps the `throws(MyError)` signature, but the handler is a plain untyped-throwing closure and the generated body re-throws its error as the declared type:

```swift
func load(id: Int) throws(LoadError) -> String
// generates:
// var loadHandler: (@Sendable (Int) throws -> String)? = nil
// do { return try _handler(id) } catch { throw error as! LoadError }
```

Configure the handler as usual (`mock.loadHandler = { id in throw LoadError() }`). This keeps the full deployment range and supports generic error types. If a handler throws a different error type, the mock traps.

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

## Initializer Requirements

A protocol `init` requirement is satisfied by a generated `required init` witness that mirrors the requirement's signature and records the call:

```swift
init(configuration: Configuration)
// generates:
// var initCallCount: Int = 0
// var initCallArgs: [Configuration] = []
// required init(configuration: Configuration) {
//     initCallCount += 1
//     initCallArgs.append(configuration)
// }
```

Initializers record only — there is no `initHandler`, because a per-instance handler could never be set before the initializer runs. `async`, `throws`, failability (`init?`), and generic clauses are preserved. When a protocol declares its own `init` requirements, the synthesized parameterless `init()` (normally generated for `public` / `package` mocks) is omitted. `resetMock()` clears `initCallCount` and `initCallArgs`. For `Sendable` and `actor` mocks the tracking is lock-backed like every other member, and the `actor` witness omits `required`.

A child mock inherits its parent mock's initializers, so a protocol whose parent declares an `init` requirement is mockable through the inherited `required init`. Declaring a new `init` requirement directly on an inheriting protocol is not yet supported and emits a diagnostic.

## Inheritance and `resetMock()`

If a protocol inherits from another protocol and a parent mock exists, the child mock inherits from the parent mock. Child `resetMock()` calls `super.resetMock()` first. The child mock inherits the parent mock's initializers (it does not synthesize its own), so a parent `init` requirement is satisfied through the inherited `required init`.

For multiple parent protocols, the first parent is used as the superclass target.

## Conditional Compilation

Protocol members inside `#if` / `#elseif` / `#else` are preserved in generated mocks. `resetMock()` includes matching conditional branches so reset behavior stays aligned with active compilation conditions.

## Diagnostics

Compilation errors are emitted when:

- `@Mockable` is applied to non-protocol declarations.
- Unsupported members are present (for example a `static subscript`).
- A new `init` requirement is declared directly on an inheriting protocol (not yet supported; inherited initializers still work).
- Arguments are passed to `@Mockable` (it accepts none).

## Current Constraints

- Static/class subscripts are not supported.
- `init` requirements are supported for standalone protocols (including `Sendable` and `actor` mocks) and are inherited by child mocks. Declaring a new `init` requirement directly on an inheriting protocol is not yet supported.
- Return-value methods and get-only subscript getters trigger `fatalError` when the handler is unset, unless the return type has a natural empty value: Optionals return `nil`, arrays and sets return an empty collection, and dictionaries return an empty dictionary.
