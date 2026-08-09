import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private var dragCoordinator: DragCoordinator?
    private var lifecycleObservers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let settings = SettingsStore.shared
        let permissions = PermissionController()
        let loginItems = LoginItemController()
        let overlay = OverlayPanelController(layouts: LayoutDefinition.builtIn)
        let coordinator = DragCoordinator(
            settings: settings,
            permissions: permissions,
            overlay: overlay,
            layouts: LayoutDefinition.builtIn
        )

        statusItemController = StatusItemController(
            settings: settings,
            permissions: permissions,
            loginItems: loginItems,
            cancelCurrentDrag: { [weak coordinator] in coordinator?.cancelCurrentDrag() }
        )
        dragCoordinator = coordinator
        coordinator.start()
        observeLifecycle(coordinator: coordinator)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            permissions.requestIfNeeded(prompt: true)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        dragCoordinator?.stop()
        lifecycleObservers.forEach { $0.center.removeObserver($0.token) }
        lifecycleObservers.removeAll()
    }

    private func observeLifecycle(coordinator: DragCoordinator) {
        let center = NotificationCenter.default
        let screenToken = center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak coordinator] _ in
            MainActor.assumeIsolated { coordinator?.displayConfigurationChanged() }
        }
        lifecycleObservers.append((center, screenToken))

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.willSleepNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.activeSpaceDidChangeNotification
        ] {
            let token = workspaceCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak coordinator] _ in
                MainActor.assumeIsolated { coordinator?.cancelCurrentDrag() }
            }
            lifecycleObservers.append((workspaceCenter, token))
        }
    }
}
