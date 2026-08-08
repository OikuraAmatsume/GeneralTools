import ApplicationServices
import CoreGraphics
import Foundation

// macOS virtual key codes: F13 = 105, Space = 49.
private let f13KeyCode: CGKeyCode = 105
private let spaceKeyCode: CGKeyCode = 49
private var eventTap: CFMachPort?

private func switchInputSource() {
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
    else { return }

    keyDown.flags = .maskControl
    keyUp.flags = .maskControl
    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)
}

private let callback: CGEventTapCallBack = { _, type, event, _ in
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

    switchInputSource()
    return nil // Consume F13 so applications do not receive it as well.
}

let accessibilityOptions = [
    kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
] as CFDictionary

guard AXIsProcessTrustedWithOptions(accessibilityOptions) else {
    fputs("请在“系统设置 → 隐私与安全性 → 辅助功能”中允许本程序，然后重新运行。\n", stderr)
    exit(1)
}

let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
eventTap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: eventMask,
    callback: callback,
    userInfo: nil
)

guard let eventTap else {
    fputs("无法监听键盘。请同时检查“输入监控”和“辅助功能”权限。\n", stderr)
    exit(1)
}

let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
CGEvent.tapEnable(tap: eventTap, enable: true)

print("F13 输入法切换已启动。按 Control-C 停止。")
CFRunLoopRun()
