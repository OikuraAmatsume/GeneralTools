import AppKit

@MainActor
final class ApplicationController: NSObject {
    private enum Phase {
        case noRegion
        case ready
        case preparing
        case recording
        case exporting
    }

    private let selectionController = SelectionRegionController()
    private var statusController: StatusItemController?
    private var recordingEngine: RecordingEngine?
    private var settings = RecordingSettings()
    private var phase: Phase = .noRegion {
        didSet { statusController?.update(isRecording: phase == .recording) }
    }
    private var terminationRequested = false

    var needsTerminationDelay: Bool {
        phase == .preparing || phase == .recording || phase == .exporting
    }

    func start() {
        statusController = StatusItemController { [weak self] in
            self?.makeMenu() ?? NSMenu()
        }
    }

    func requestQuit() {
        terminationRequested = true
        switch phase {
        case .recording:
            stopRecording()
        case .preparing, .exporting:
            break
        case .noRegion, .ready:
            NSApp.reply(toApplicationShouldTerminate: true)
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        switch phase {
        case .noRegion:
            menu.addItem(item("録画範囲を作成", action: #selector(createRegion)))
            menu.addItem(.separator())
            menu.addItem(item("終了", action: #selector(quit)))

        case .ready:
            menu.addItem(item("録画を開始", action: #selector(startRecording)))
            menu.addItem(item("録画範囲を再作成", action: #selector(recreateRegion)))
            menu.addItem(.separator())
            menu.addItem(formatMenuItem())
            menu.addItem(frameRateMenuItem())
            menu.addItem(scaleMenuItem())
            menu.addItem(.separator())
            menu.addItem(item("終了", action: #selector(quit)))

        case .preparing:
            let preparing = NSMenuItem(title: "録画を準備中…", action: nil, keyEquivalent: "")
            preparing.isEnabled = false
            menu.addItem(preparing)
            menu.addItem(.separator())
            menu.addItem(item("終了", action: #selector(quit)))

        case .recording:
            menu.addItem(item("録画を終了", action: #selector(stopRecordingAction)))
            menu.addItem(.separator())
            menu.addItem(item("終了", action: #selector(quit)))

        case .exporting:
            let exporting = NSMenuItem(title: "書き出し中…", action: nil, keyEquivalent: "")
            exporting.isEnabled = false
            menu.addItem(exporting)
            menu.addItem(.separator())
            menu.addItem(item("終了", action: #selector(quit)))
        }
        return menu
    }

    private func item(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func formatMenuItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "出力形式：\(settings.format.title)", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "出力形式")
        for format in RecordingFormat.allCases {
            let child = item(format.title, action: #selector(selectFormat(_:)))
            child.tag = format.rawValue
            child.state = settings.format == format ? .on : .off
            submenu.addItem(child)
        }
        parent.submenu = submenu
        return parent
    }

    private func frameRateMenuItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "フレームレート：\(settings.frameRate) fps", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "フレームレート")
        for frameRate in RecordingSettings.availableFrameRates {
            let child = item("\(frameRate) fps", action: #selector(selectFrameRate(_:)))
            child.tag = frameRate
            child.state = settings.frameRate == frameRate ? .on : .off
            submenu.addItem(child)
        }
        parent.submenu = submenu
        return parent
    }

    private func scaleMenuItem() -> NSMenuItem {
        let percentage = Int((settings.outputScale * 100).rounded())
        let parent = NSMenuItem(title: "スケール：\(percentage)%", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "スケール")
        for scale in RecordingSettings.availableScales {
            let value = Int((scale * 100).rounded())
            let child = item("\(value)%", action: #selector(selectScale(_:)))
            child.tag = value
            child.state = settings.outputScale == scale ? .on : .off
            submenu.addItem(child)
        }
        parent.submenu = submenu
        return parent
    }

    @objc private func createRegion() {
        selectionController.createDefaultRegion()
        phase = selectionController.hasRegion ? .ready : .noRegion
    }

    @objc private func recreateRegion() {
        selectionController.createDefaultRegion()
        phase = selectionController.hasRegion ? .ready : .noRegion
    }

    @objc private func selectFormat(_ sender: NSMenuItem) {
        guard let format = RecordingFormat(rawValue: sender.tag) else { return }
        settings.format = format
    }

    @objc private func selectFrameRate(_ sender: NSMenuItem) {
        guard RecordingSettings.availableFrameRates.contains(sender.tag) else { return }
        settings.frameRate = sender.tag
    }

    @objc private func selectScale(_ sender: NSMenuItem) {
        let scale = Double(sender.tag) / 100
        guard RecordingSettings.availableScales.contains(scale) else { return }
        settings.outputScale = scale
    }

    @objc private func startRecording() {
        guard phase == .ready,
              let descriptor = selectionController.descriptor() else {
            return
        }

        selectionController.setLocked(true)
        phase = .preparing

        let currentSettings = settings
        Task { [weak self] in
            guard let self else { return }

            guard await ScreenRecordingPermission.ensureGranted() else {
                selectionController.setLocked(false)
                phase = selectionController.hasRegion ? .ready : .noRegion
                completePendingTerminationIfNeeded()
                return
            }

            guard !terminationRequested else {
                selectionController.setLocked(false)
                phase = selectionController.hasRegion ? .ready : .noRegion
                completePendingTerminationIfNeeded()
                return
            }

            let destination: URL
            do {
                destination = try OutputDestination.makeURL(for: currentSettings.format)
            } catch {
                selectionController.setLocked(false)
                phase = selectionController.hasRegion ? .ready : .noRegion
                showError(title: "无法准备输出文件夹", error: error)
                completePendingTerminationIfNeeded()
                return
            }

            let engine = RecordingEngine()
            recordingEngine = engine
            engine.onUnexpectedStop = { [weak self] error in
                self?.recordingFailed(error)
            }

            do {
                try await engine.start(
                    descriptor: descriptor,
                    settings: currentSettings,
                    destinationURL: destination
                )
                phase = .recording
                if terminationRequested {
                    stopRecording()
                }
            } catch {
                engine.abort()
                recordingEngine = nil
                selectionController.setLocked(false)
                phase = selectionController.hasRegion ? .ready : .noRegion
                showError(title: "无法开始录制", error: error)
                completePendingTerminationIfNeeded()
            }
        }
    }

    @objc private func stopRecordingAction() {
        stopRecording()
    }

    private func stopRecording() {
        guard phase == .recording, let engine = recordingEngine else { return }
        phase = .exporting

        Task { [weak self] in
            guard let self else { return }
            do {
                let outputURL = try await engine.stopAndExport()
                recordingEngine = nil
                selectionController.setLocked(false)
                phase = selectionController.hasRegion ? .ready : .noRegion
                if !terminationRequested {
                    NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                }
            } catch {
                engine.abort()
                recordingEngine = nil
                selectionController.setLocked(false)
                phase = selectionController.hasRegion ? .ready : .noRegion
                showError(title: "导出失败", error: error)
            }
            completePendingTerminationIfNeeded()
        }
    }

    private func recordingFailed(_ error: Error) {
        guard phase == .recording || phase == .preparing else { return }
        recordingEngine?.abort()
        recordingEngine = nil
        selectionController.setLocked(false)
        phase = selectionController.hasRegion ? .ready : .noRegion
        showError(title: "录制意外停止", error: error)
        completePendingTerminationIfNeeded()
    }

    private func showError(title: String, error: Error) {
        guard !terminationRequested else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(error: error)
        alert.messageText = title
        alert.runModal()
    }

    private func completePendingTerminationIfNeeded() {
        guard terminationRequested else { return }
        selectionController.close()
        NSApp.reply(toApplicationShouldTerminate: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
