/// A macro that generates a mock class for a protocol.
///
/// When applied to a protocol, this macro generates a `Mock<ProtocolName>` class
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
/// This generates a `MockUserService` class with:
/// - Handlers for each method that can be configured
/// - Call tracking for verification
/// - Property stubs
///
@attached(peer, names: prefixed(Mock))
public macro Mockable() = #externalMacro(module: "MockableMacros", type: "MockableMacro")
