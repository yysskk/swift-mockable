import Foundation
import Mockable

// MARK: - Basic Test Protocols

@Mockable
protocol SimpleService {
    func doSomething()
    func getValue() -> String
}

@Mockable
protocol AsyncService {
    func fetchData(id: Int) async throws -> String
}

@Mockable
protocol ServiceWithProperties {
    var readOnlyValue: Int { get }
    var readWriteValue: String { get set }
    var optionalValue: Double? { get set }
}

@Mockable
protocol MultiParameterService {
    func calculate(a: Int, b: Int, c: Int) -> Int
}

@Mockable
protocol GenericService {
    func get<T>(_ key: String) -> T
    func set<T>(_ value: T, forKey key: String)
}

@Mockable
protocol EventHandlerService {
    func subscribe(eventHandler: @escaping (String) -> Void)
    func onEvent(callback: @escaping @Sendable (Int) -> Void)
}

@Mockable
protocol SendableEventService: Sendable {
    func register(eventCallback: @escaping @Sendable (String) -> Void) async
}

// MARK: - Overloaded Method Protocols

@Mockable
protocol OverloadedUserDefaults: Sendable {
    func set(_ value: Bool, forKey: String) async
    func set(_ value: Int, forKey: String) async
    func set(_ value: String, forKey: String) async
    func getValue() async -> String
}

@Mockable
protocol ActorOverloadedService: Actor {
    func process(_ value: Int) async
    func process(_ value: String) async
    func fetch() async -> String
}
