import ApplicationServices
import Carbon
import CoreGraphics
import Foundation
import OSLog

enum F13Action: String, CaseIterable {
    case switchInputSource
    case simplifiedChinese

    private static let defaultsKey = "selectedF13Action"

    var menuTitle: String {
        switch self {
        case .switchInputSource:
            return "输入法切换"
        case .simplifiedChinese:
            return "简体中文"
        }
    }

    static var selected: F13Action {
        get {
            guard
                let storedValue = UserDefaults.standard.string(forKey: defaultsKey),
                let action = F13Action(rawValue: storedValue)
            else {
                return .simplifiedChinese
            }

            return action
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }
}

final class KeyboardMonitor {
    enum State: Equatable {
        case stopped
        case permissionRequired
        case running
        case failed
    }

    var onStateChange: ((State) -> Void)?

    private(set) var state: State = .stopped {
        didSet {
            guard state != oldValue else { return }
            onStateChange?(state)
        }
    }

    private let f13KeyCode: CGKeyCode = 105
    private let spaceKeyCode: CGKeyCode = 49
    private let vKeyCode: CGKeyCode = 9
    private let simplifiedChineseInputSourceID = "com.apple.inputmethod.SCIM.ITABC"
    private let logger = Logger(
        subsystem: "com.amatsume.AmatsumeInit",
        category: "KeyboardMonitor"
    )
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let finderClipboardImagePaster = FinderClipboardImagePaster()

    var f13Action: F13Action = .selected {
        didSet {
            guard f13Action != oldValue else { return }
            F13Action.selected = f13Action
            logger.notice("F13 功能已切换为：\(self.f13Action.menuTitle, privacy: .public)")
        }
    }

    @discardableResult
    func start(promptForPermission: Bool) -> Bool {
        guard state != .running else { return true }

        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: promptForPermission
        ] as CFDictionary

        guard AXIsProcessTrustedWithOptions(options) else {
            state = .permissionRequired
            return false
        }

        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: keyboardEventCallback,
            userInfo: userInfo
        ) else {
            state = .failed
            return false
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            eventTap,
            0
        )

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource

        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        state = .running
        return true
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }

        runLoopSource = nil
        eventTap = nil
        state = .stopped
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let isAutoRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        if keyCode == f13KeyCode {
            if !isAutoRepeat {
                performF13Action()
            }

            return nil
        }

        if keyCode == vKeyCode, isCommandOnly(event.flags) {
            if isAutoRepeat {
                return finderClipboardImagePaster.canHandlePasteShortcut()
                    ? nil
                    : Unmanaged.passUnretained(event)
            }

            if finderClipboardImagePaster.saveClipboardImageInFocusedFinderWindow() {
                return nil
            }
        }

        return Unmanaged.passUnretained(event)
    }

    private func isCommandOnly(_ flags: CGEventFlags) -> Bool {
        let disallowedModifiers: CGEventFlags = [.maskShift, .maskControl, .maskAlternate]
        return flags.contains(.maskCommand) && flags.intersection(disallowedModifiers).isEmpty
    }

    private func performF13Action() {
        switch f13Action {
        case .switchInputSource:
            sendInputSourceShortcut()
        case .simplifiedChinese:
            selectSimplifiedChineseInputSource()
        }
    }

    private func sendInputSourceShortcut() {
        guard
            let source = CGEventSource(stateID: .hidSystemState),
            let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: spaceKeyCode,
                keyDown: true
            ),
            let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: spaceKeyCode,
                keyDown: false
            )
        else {
            logger.error("无法生成输入法切换快捷键")
            return
        }

        keyDown.flags = .maskControl
        keyUp.flags = .maskControl
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        logger.notice("F13 已触发输入法切换")
    }

    private func selectSimplifiedChineseInputSource() {
        let properties = [
            kTISPropertyInputSourceID as String: simplifiedChineseInputSourceID
        ] as CFDictionary
        let sources = TISCreateInputSourceList(properties, false)
            .takeRetainedValue() as NSArray

        guard let inputSource = sources.firstObject as! TISInputSource? else {
            logger.error(
                "未找到简体中文输入源：\(self.simplifiedChineseInputSourceID, privacy: .public)"
            )
            return
        }

        let result = TISSelectInputSource(inputSource)

        if result == noErr {
            logger.notice("F13 已切换到简体中文")
        } else {
            logger.error("切换简体中文失败，错误码：\(result)")
        }
    }
}

private let keyboardEventCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let monitor = Unmanaged<KeyboardMonitor>
        .fromOpaque(userInfo)
        .takeUnretainedValue()

    return monitor.handle(type: type, event: event)
}
