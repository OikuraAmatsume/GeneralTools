import AppKit
import ApplicationServices
import OSLog
import UniformTypeIdentifiers

final class FinderClipboardImagePaster {
    private let finderBundleIdentifier = "com.apple.finder"
    private let logger = Logger(
        subsystem: "com.amatsume.AmatsumeInit",
        category: "FinderClipboardImagePaster"
    )

    func canHandlePasteShortcut() -> Bool {
        isFinderFrontmost
            && !isFinderTextInputFocused
            && clipboardContainsImage
    }

    @discardableResult
    func saveClipboardImageInFocusedFinderWindow() -> Bool {
        guard isFinderFrontmost else { return false }
        guard !isFinderTextInputFocused else { return false }
        guard let pngData = clipboardPNGData() else { return false }

        DispatchQueue.global(qos: .userInitiated).async { [weak self, logger] in
            guard let self else { return }

            guard let directoryURL = self.frontFinderDirectoryURL() else {
                logger.error("无法读取当前 Finder 窗口目录")
                return
            }

            let fileURL = self.availableFileURL(in: directoryURL, date: Date())

            do {
                try pngData.write(to: fileURL, options: .withoutOverwriting)
                logger.notice("已保存剪贴板图片：\(fileURL.path, privacy: .public)")

                DispatchQueue.main.async {
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                }
            } catch {
                logger.error("保存剪贴板图片失败：\(error.localizedDescription, privacy: .public)")
            }
        }

        return true
    }

    private var isFinderFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == finderBundleIdentifier
    }

    private var clipboardContainsImage: Bool {
        clipboardImageType() != nil
    }

    private var isFinderTextInputFocused: Bool {
        guard
            let finder = activeFinderApplication(),
            let focusedElement = copiedAXElement(
                attribute: kAXFocusedUIElementAttribute as CFString,
                from: AXUIElementCreateApplication(finder.processIdentifier)
            ),
            let role = copiedAXString(
                attribute: kAXRoleAttribute as CFString,
                from: focusedElement
            )
        else {
            return false
        }

        return role == kAXTextFieldRole || role == kAXTextAreaRole || role == kAXComboBoxRole
    }

    private func clipboardPNGData() -> Data? {
        let pasteboard = NSPasteboard.general

        if let pngData = pasteboard.data(forType: .png) {
            return pngData
        }

        guard let imageType = clipboardImageType() else {
            return nil
        }

        if
            let imageData = pasteboard.data(forType: imageType),
            let bitmap = NSBitmapImageRep(data: imageData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        {
            return pngData
        }

        guard
            let image = NSImage(pasteboard: pasteboard),
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }

    private func clipboardImageType() -> NSPasteboard.PasteboardType? {
        let pasteboard = NSPasteboard.general

        // Copying an image file in Finder can expose both a file URL and image
        // representations. Preserve Finder's normal file-copy behavior.
        guard pasteboard.availableType(from: [.fileURL]) == nil else { return nil }

        return pasteboard.types?.first { pasteboardType in
            guard let type = UTType(pasteboardType.rawValue) else { return false }
            return type.conforms(to: .image)
        }
    }

    private func frontFinderDirectoryURL() -> URL? {
        let source = """
        tell application id "com.apple.finder"
            if (count of Finder windows) is 0 then
                return POSIX path of (desktop as alias)
            end if
            return POSIX path of (target of front Finder window as alias)
        end tell
        """
        var errorInfo: NSDictionary?

        guard
            let script = NSAppleScript(source: source),
            let path = script.executeAndReturnError(&errorInfo).stringValue
        else {
            let message = errorInfo?[NSAppleScript.errorMessage] as? String ?? "未知错误"
            logger.error("读取 Finder 当前目录失败：\(message, privacy: .public)")
            return nil
        }

        let directoryURL = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL

        guard
            directoryURL.isFileURL,
            (try? directoryURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        else {
            return nil
        }

        return directoryURL
    }

    private func activeFinderApplication() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(
            withBundleIdentifier: finderBundleIdentifier
        ).first(where: \.isActive)
    }

    private func copiedAXElement(attribute: CFString, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?

        guard
            AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
            let value
        else {
            return nil
        }

        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func copiedAXString(attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?

        guard
            AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
            let value
        else {
            return nil
        }

        return value as? String
    }

    private func availableFileURL(in directory: URL, date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd_HHmmss_SSS"

        let timestamp = formatter.string(from: date)

        for index in 1...10_000 {
            let suffix = index == 1 ? "" : "_\(index)"
            let fileURL = directory.appendingPathComponent(
                "\(timestamp)\(suffix).png",
                isDirectory: false
            )

            if !FileManager.default.fileExists(atPath: fileURL.path) {
                return fileURL
            }
        }

        return directory.appendingPathComponent(
            "\(timestamp)_\(UUID().uuidString).png",
            isDirectory: false
        )
    }
}
