// Re-export Synchronization when available for clients that use it alongside Mockable.
#if canImport(Synchronization)
@_exported import Synchronization
#endif

/// A macro that generates a mock class for a protocol.
///
/// When applied to a protocol, this macro generates a `<ProtocolName>Mock` class
/// that implements the protocol with configurable behavior for testing.
///
/// ## Usage
///
/// ```swift
/// @Mockable
/// protocol UserService {
///     func fetchUser(id: Int) async throws -> User
///     var currentUser: User? { get }
/// }
/// ```
///
/// This generates a `UserServiceMock` class with:
/// - Handlers for each method that can be configured
/// - Call tracking for verification
/// - Property stubs
///
/// ## Choosing When the Mock Is Compiled
///
/// By default the generated mock is wrapped in `#if DEBUG`. Pass a
/// ``MockCompilationCondition`` to guard it with a custom flag instead, or to
/// emit it unconditionally:
///
/// ```swift
/// @Mockable(condition: .custom("MOCKING"))
/// protocol PaymentService { ... }   // mock wrapped in #if MOCKING
///
/// @Mockable(condition: .always)
/// protocol PreviewDataService { ... }   // mock has no #if guard
/// ```
///
/// - Parameter condition: The compilation condition that guards the generated
///   mock. Defaults to ``MockCompilationCondition/debug``. The value must be
///   written literally at the attachment site (`.debug`, `.always`, or
///   `.custom("FLAG")` with a string literal).
@attached(peer, names: suffixed(Mock))
public macro Mockable(
    condition: MockCompilationCondition = .debug
) = #externalMacro(module: "MockableMacros", type: "MockableMacro")
