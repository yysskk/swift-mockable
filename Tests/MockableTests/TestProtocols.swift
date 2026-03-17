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
protocol VariadicService {
    func log(_ messages: String...)
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
protocol StaticService {
    static func makeIdentifier(prefix: String) -> String
    static var readOnlyToken: String { get }
    static var cachedValue: String? { get set }
    static var retryCount: Int { get set }
}

@Mockable
protocol SendableEventService: Sendable {
    func register(eventCallback: @escaping @Sendable (String) -> Void) async
}

@Mockable
protocol InoutSortingService {
    func sort(_ array: inout [Int])
}

@Mockable
protocol InoutWithReturnService {
    func removeFirst(_ array: inout [String]) -> String
}

@Mockable
protocol MultipleInoutService {
    func swap(_ a: inout Int, _ b: inout Int)
}

@Mockable
protocol InoutThrowsService {
    func parse(_ buffer: inout [UInt8]) throws -> String
}

@Mockable
protocol InoutAsyncService {
    func process(_ data: inout [Int]) async -> Int
}

@Mockable
protocol InoutGenericService {
    func transform<T>(_ value: inout T)
}

// MARK: - MainActor Protocols

@Mockable
@MainActor
protocol MainActorPresenter {
    func loadData()
    func fetchItems() async throws -> [String]
    var title: String { get }
    var subtitle: String { get set }
    var optionalNote: String? { get set }
}

// MARK: - Protocol Inheritance

@Mockable
protocol BaseService {
    func baseMethod() -> String
    var baseName: String { get }
}

@Mockable
protocol ChildService: BaseService {
    func childMethod() -> Int
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
