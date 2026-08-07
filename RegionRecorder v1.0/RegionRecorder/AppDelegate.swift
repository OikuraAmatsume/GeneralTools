import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var applicationController: ApplicationController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let controller = ApplicationController()
        applicationController = controller
        controller.start()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let applicationController, applicationController.needsTerminationDelay else {
            return .terminateNow
        }

        applicationController.requestQuit()
        return .terminateLater
    }
}
