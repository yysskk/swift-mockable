# Migrating to 3.0

Update tests written against Mockable 2.x for the renamed and reshaped members of 3.0.

## Overview

Mockable 3.0 renames and reshapes a few generated members so that the API a test
writes against follows the Swift API Design Guidelines. Most of the changes below are
compile-time breaks, where the compiler points at each place to update. The exception
is resetting `static` state: a test that relied on an instance's `resetMock()` to clear
it still compiles, but the state now survives the call, so review those tests by hand.

## Update the Dependency

```swift
.package(url: "https://github.com/yysskk/swift-mockable.git", from: "3.0.0")
```

## `CallArgs` Is Now `CallArguments`

The member that records each call's arguments is spelled out in full, like
`CallCount` and `Handler`. Rename every `<name>CallArgs` to `<name>CallArguments`:

```swift
// 2.x
#expect(mock.fetchUserCallArgs == [42])

// 3.0
#expect(mock.fetchUserCallArguments == [42])
```

This applies to methods, subscripts (`subscriptIntCallArguments`), and initializers
(`initCallArguments`) alike. A project-wide find-and-replace of `CallArgs` with
`CallArguments` covers it.

## Set Up a Property Through the Property Itself

The `_<property>` backing member is gone. The mock's property is settable even for a
`{ get }` requirement, so set it directly:

```swift
// 2.x
mock._currentUser = User(id: 1)

// 3.0
mock.currentUser = User(id: 1)
```

On an `actor` mock the property is `nonisolated`, so setup still needs no `await`. A
non-optional property still traps when read before it is set. The one thing a test
can no longer do is read the unset state as `nil` (`mock._currentUser == nil`); a test
that needs to know whether a property was set should track that itself.

## Reset `static` State Through the Mock Type

An instance's `resetMock()` now clears only that instance's state. The state of
`static` requirements, which every instance shares, is cleared by the type-level
`resetStaticMock()`:

```swift
// 2.x — cleared instance and static state together
mock.resetMock()

// 3.0
mock.resetMock()                // instance state
ServiceMock.resetStaticMock()   // static state
```

Add the type-level call wherever a test relied on an instance reset to clear static
call counts, arguments, or handlers. Because static state is shared by every test that
uses the mock type, and Swift Testing runs tests in parallel by default, a static
requirement is best exercised by a mock type that only one test uses, or by a
`.serialized` suite.

Every class mock declares the type-level `resetStaticMock()`, with an empty body when
the protocol has no `static` requirement: it is a `class` method, and a child mock's
overrides its parent's and calls `super.resetStaticMock()` first, as the instance method
does. An actor mock declares it only when the protocol has `static` requirements.

`resetStaticMock()` was spelled `resetMock()` in 3.0.0 itself, sharing the instance
method's name; it was renamed so that the two resets cannot be mistaken for each other.


## Import `Synchronization` Yourself

`import Mockable` no longer re-exports the `Synchronization` module. Generated code
does not need it, so most projects are unaffected. A file that used `Mutex`, `Atomic`,
or another type from that module through `import Mockable` alone adds its own import:

```swift
import Mockable
import Synchronization
```

## New in 3.0

The `condition:` argument of `@Mockable` now accepts a string literal, so
`@Mockable(condition: "MOCKING")` is the same as `@Mockable(condition: .custom("MOCKING"))`.
The `.custom` spelling keeps working. See the [CHANGELOG](https://github.com/yysskk/swift-mockable/blob/main/CHANGELOG.md) for the full
list of changes.
