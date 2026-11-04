#if os(iOS)
import CarPlay

@MainActor final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var controller: CarPlayController?
    private var connection: Task<Void, Never>?
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        connection?.cancel()
        let controller = CarPlayController(store: AppSession.shared.store)
        self.controller = controller
        connection = Task {
            await AppSession.shared.start()
            guard !Task.isCancelled else { return }
            controller.connect(interfaceController)
        }
    }
    func contentStyleDidChange(_ contentStyle: UIUserInterfaceStyle) { controller?.refreshContentStyle() }
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        connection?.cancel(); connection = nil
        controller?.disconnect(); controller = nil
    }
}
#endif
