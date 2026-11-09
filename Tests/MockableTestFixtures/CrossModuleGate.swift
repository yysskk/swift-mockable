import Mockable

@Mockable
protocol CrossModuleGate {
    func open()
    func callAsFunction() -> Bool
}
