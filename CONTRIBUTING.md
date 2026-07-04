# Contributing

Thanks for your interest in improving swift-mockable! This guide covers the
project layout, how to build and test, and the conventions we follow.

## Project layout

- `Sources/Mockable/` — the runtime module clients depend on. It declares the
  `@Mockable` macro and the `MockableLock` used by generated `Sendable`/actor
  mocks.
- `Sources/MockableMacros/` — the macro implementation (built on
  [swift-syntax](https://github.com/swiftlang/swift-syntax)). `MockableMacro`
  is the entry point; the `MockGenerator+*` files generate each kind of member.
- `Tests/MockableMacroTests/` — macro-expansion tests that pin the exact
  generated source.
- `Tests/MockableTests/` — runtime tests that exercise the behavior of
  generated mocks.

## Building and testing

```sh
swift build
swift test
```

Tests use [swift-testing](https://github.com/swiftlang/swift-testing) (`@Test` /
`#expect`), which ships with Swift 6 toolchains. On Swift 5.9 / 5.10 the package
builds but the test suite is Swift 6 only.

### Swift version compatibility

The package supports Swift 5.9, 5.10, and 6.2+. Each toolchain resolves a
different swift-syntax major version, so there are three manifests:

- `Package.swift` (Swift 6.2+, swift-syntax 603)
- `Package@swift-5.10.swift` (swift-syntax 510)
- `Package@swift-5.9.swift` (swift-syntax 509)

Any use of a version-sensitive swift-syntax API must go through a shim in
`Sources/MockableMacros/SwiftSyntaxCompatibility.swift` so it compiles against
all three.

## Writing tests

Most changes should include both:

- A **macro-expansion test** in `Tests/MockableMacroTests/`, using the
  `assertMacroExpansionForTesting(_:expandedSource:diagnostics:macros:)` helper.
  It wraps swift-syntax's `assertMacroExpansion` and reports mismatches through
  swift-testing. Paste the input protocol and the exact expected expansion; if
  the whitespace is hard to predict, run the test once and copy the "Actual
  expanded source" from the failure.
- A **runtime test** in `Tests/MockableTests/`, adding the protocol to
  `TestProtocols.swift` and asserting the generated mock behaves as expected.

Diagnostics are tested by passing a `diagnostics:` array to
`assertMacroExpansionForTesting`.

## Keeping documentation in sync

When a change affects generated output or user-facing behavior, update all of
these together so they don't drift:

- `README.md`
- `docs/advanced-usage.md`
- `llms.txt` and `llms-full.txt`
- the DocC catalog under `Sources/Mockable/Mockable.docc/`

## Commit and PR conventions

- Use [Conventional Commits](https://www.conventionalcommits.org/) for commit
  and PR titles (`feat:`, `fix:`, `refactor:`, `chore:`, `ci:`, `docs:`).
- Keep pull requests focused and reviewable.
- Fill in the pull request template, including the testing and docs checklist.
