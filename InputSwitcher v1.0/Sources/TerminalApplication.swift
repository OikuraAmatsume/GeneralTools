import AppKit
import OSLog

enum TerminalApplication: String, CaseIterable {
    case terminal
    case iTerm2
    case warp
    case ghostty
    case wezTerm

    static let defaultsKey = "defaultTerminalApplication"

    var displayName: String {
        switch self {
        case .terminal: return "Terminal"
        case .iTerm2: return "iTerm2"
        case .warp: return "Warp"
        case .ghostty: return "Ghostty"
        case .wezTerm: return "WezTerm"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .terminal: return "com.apple.Terminal"
        case .iTerm2: return "com.googlecode.iterm2"
        case .warp: return "dev.warp.Warp-Stable"
        case .ghostty: return "com.mitchellh.ghostty"
        case .wezTerm: return "com.github.wez.wezterm"
        }
    }

    var applicationURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    var isAvailable: Bool {
        applicationURL != nil
    }

    static var selected: TerminalApplication {
        get {
            guard
                let storedValue = UserDefaults.standard.string(forKey: defaultsKey),
                let terminal = TerminalApplication(rawValue: storedValue),
                terminal.isAvailable
            else {
                return .terminal
            }

            return terminal
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }

    static var availableApplications: [TerminalApplication] {
        allCases.filter(\.isAvailable)
    }
}

final class TerminalLauncher {
    private let logger = Logger(
        subsystem: "com.amatsume.AmatsumeInit",
        category: "TerminalLauncher"
    )

    func open(directory: URL) {
        let standardizedDirectory = directory.standardizedFileURL

        guard
            standardizedDirectory.isFileURL,
            (try? standardizedDirectory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        else {
            return
        }

        let terminal = TerminalApplication.selected

        if terminal == .iTerm2 {
            openITerm2(directory: standardizedDirectory)
            return
        }

        guard let applicationURL = terminal.applicationURL else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        NSWorkspace.shared.open(
            [standardizedDirectory],
            withApplicationAt: applicationURL,
            configuration: configuration
        )
    }

    private func openITerm2(directory: URL) {
        let targetPath = directory.path

        DispatchQueue.global(qos: .userInitiated).async { [logger] in
            let process = Process()
            let errorPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = [
                "-e", "on run argv",
                "-e", "set targetPath to item 1 of argv",
                "-e", "set shellCommand to \"cd -- \" & quoted form of targetPath & \"; exec \\\"${SHELL:-/bin/zsh}\\\" -l\"",
                "-e", "set launchCommand to \"/bin/zsh -lc \" & quoted form of shellCommand",
                "-e", "tell application id \"com.googlecode.iterm2\"",
                "-e", "activate",
                "-e", "create window with default profile command launchCommand",
                "-e", "end tell",
                "-e", "end run",
                targetPath
            ]
            process.standardError = errorPipe

            do {
                try process.run()
                process.waitUntilExit()

                guard process.terminationStatus != 0 else {
                    logger.notice("iTerm2 已打开目录：\(targetPath, privacy: .public)")
                    return
                }

                let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: data, encoding: .utf8) ?? "未知错误"
                logger.error("iTerm2 启动失败：\(message, privacy: .public)")
            } catch {
                logger.error("无法执行 iTerm2 启动脚本：\(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
