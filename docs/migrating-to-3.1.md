# Migrating to 3.1

Mockable 3.1 continues the naming work of 3.0 and includes source-breaking changes.
Each of them is a compile-time break, so the compiler points at every place to update.

## Update the Dependency

```swift
.package(url: "https://github.com/yysskk/swift-mockable.git", from: "3.1.0")
```

## Reset `static` State with `resetStaticMock()`

The type-level reset that 3.0 introduced is renamed so that it can no longer be
mistaken for the instance's `resetMock()`, which resets something else:

```swift
// 3.0
ServiceMock.resetMock()

// 3.1
ServiceMock.resetStaticMock()
```

A class mock still declares it even when the protocol has no `static` requirement, so
that a child mock can override it. An actor mock now declares it only when the protocol
has `static` requirements; remove calls to it on an actor mock that has none.

## Overloads Are Named After Their Argument Labels

An overloaded method or initializer is named after its argument labels instead of its
parameter types, so a test reads like the call it checks:

```swift
protocol ItemStore {
    func fetch(id: Int) -> Item
    func fetch(name: String) -> Item
}

// 3.0
mock.fetchIntHandler = { id in Item(id: id) }
#expect(mock.fetchStringCallCount == 1)

// 3.1
mock.fetchIDHandler = { id in Item(id: id) }
#expect(mock.fetchNameCallCount == 1)
```

Each label is capitalized, and a leading common acronym (`id`, `url`, `http`, `json`,
...) is uppercased. Overloaded initializers follow the same rule: `init(host:)` and
`init(host:port:)` generate `initHost...` and `initHostPort...`. Overloads whose labels
coincide, such as `save(_:)` taking different types, keep the type-based suffix, and
subscripts are unchanged.

## Call History Is Read-Only

`<name>CallCount` and `<name>CallArguments` can no longer be assigned outside the mock.
A test that assigned them to start over calls `resetMock()` instead:

```swift
// 3.0
mock.fetchUserCallCount = 0
mock.fetchUserCallArguments = []

// 3.1
mock.resetMock()
```

`resetMock()` also clears the instance's handlers and stored properties, so set up
again what the rest of the test needs. Handlers and properties stay writable.

## A Module-Qualified Parent Is a Conformance

A parent protocol named with a module qualifier other than `Swift.` is no longer a
parent whose mock is subclassed. The mock conforms to it and witnesses the requirements
restated in the protocol's own body. A protocol that used a qualifier to subclass a
parent mock names the parent without one:

```swift
// 3.0 — `ServiceMock` subclassed `Core.RepositoryMock`
@Mockable
protocol Service: Core.Repository { ... }

// 3.1
@Mockable
protocol Service: Repository { ... }
```

This is what makes a protocol from another module mockable: restate its requirements
in a protocol that refines it, and `@Mockable` generates a mock that conforms to the
original. [kmp-swift-mockable](https://github.com/yysskk/kmp-swift-mockable) generates
such protocols for Kotlin Multiplatform interfaces.

## `MockCompilationCondition` Is No Longer `Equatable`

The macro reads the condition from the attribute's syntax, so the type is never
compared at run time. Code that compared two conditions compares the spellings it
passed to them instead.

## Deprecations

Both of these keep compiling with a warning, and are removed in the next major release:

- `MockableLock` is renamed `_MockableLock`. Generated code already uses the new name;
  only code that referenced the type by hand needs updating.
- `<name>CallArguments` of a requirement without arguments to record, such as
  `func refresh()`, is computed from the call count. Read `<name>CallCount` instead:

  ```swift
  // 3.0
  #expect(mock.refreshCallArguments.count == 1)

  // 3.1
  #expect(mock.refreshCallCount == 1)
  ```

## New in 3.1

A plain mock's handlers are ordinary closures instead of `@Sendable` ones, so a handler
can capture and mutate a test's local state:

```swift
var messages: [String] = []
mock.logHandler = { messages.append($0) }
```

Handlers stay `@Sendable` on `Sendable`, `actor`, and global-actor-isolated mocks, and
for `static` requirements. See the [CHANGELOG](../CHANGELOG.md) for the full list of
changes.
