/// Production code calling mocked protocols from a different file than the mocks.
@MainActor
final class CrossModulePresenter {
    private let view: any CrossModuleView
    private let wireframe: any CrossModuleWireframe

    init(view: any CrossModuleView, wireframe: any CrossModuleWireframe) {
        self.view = view
        self.wireframe = wireframe
    }

    func didAppear() {
        view.showLoading()
        view.show(title: "Title")
    }

    func didTapDone() {
        wireframe.complete()
    }

    func didTapClose() {
        wireframe.skip()
    }
}
