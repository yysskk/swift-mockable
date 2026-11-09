import Mockable

@Mockable
protocol CrossModuleAsyncGate {
    func reset()
    func callAsFunction() async -> Bool
}
