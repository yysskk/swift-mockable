import Mockable

@Mockable
@MainActor
protocol CrossModuleView {
    func showLoading()
    func show(title: String)
}
