import AppKit
import ApplicationServices

@MainActor
final class PermissionController {
    var isTrusted: Bool { AXIsProcessTrusted() }

    @discardableResult
    func requestIfNeeded(prompt: Bool) -> Bool {
        guard !isTrusted else { return true }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
