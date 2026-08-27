import ApplicationServices
import Carbon
import CoreGraphics
import Foundation
import OSLog

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
    private let simplifiedChineseInputSourceID = "com.apple.inputmethod.SCIM.ITABC"
    private let logger = Logger(
        subsystem: "com.amatsume.AmatsumeInit",
        category: "KeyboardMonitor"
    )
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

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

        guard
            type == .keyDown,
            CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)) == f13KeyCode
        else {
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            selectSimplifiedChineseInputSource()
        }

        return nil
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
