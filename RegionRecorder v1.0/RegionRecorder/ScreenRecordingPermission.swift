import AppKit
import CoreGraphics
import ScreenCaptureKit

@MainActor
enum ScreenRecordingPermission {
    static func ensureGranted() async -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }

        NSApp.activate(ignoringOtherApps: true)

        // Query ScreenCaptureKit directly so macOS registers this .app bundle with TCC.
        // Apple's ScreenCaptureKit sample uses this path for the first-run permission prompt.
        // CGPreflightScreenCaptureAccess remains useful as a fast path after permission exists.
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            return true
        } catch {
            showPermissionHelp()
            return false
        }
    }

    private static func showPermissionHelp() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "需要屏幕录制权限"
        alert.informativeText = "请在“系统设置 → 隐私与安全性 → 屏幕与系统音频录制”中允许“本地区域录屏”，然后退出并重新打开应用。\n\n如果列表中没有本应用：先在 Xcode 的 Signing & Capabilities 中选择你的 Team；也可以点列表左下角“+”，再选择访达中显示的本应用。应用不会申请麦克风权限。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "在访达中显示应用")
        alert.addButton(withTitle: "取消")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        case .alertSecondButtonReturn:
            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
        default:
            break
        }
    }
}
