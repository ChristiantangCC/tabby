import Cocoa

/// Switcher shortcut (⌥Tab by default) handled through a session event tap (needs Accessibility).
/// While the switcher is open it swallows every key, so nothing leaks to the app underneath.
final class HotKeys {
    static let shared = HotKeys()

    var isActive: () -> Bool = { false }
    var onOpen: (_ backwards: Bool) -> Void = { _ in }
    var onStep: (_ delta: Int) -> Void = { _ in }
    var onCommit: () -> Void = {}
    var onCancel: () -> Void = {}
    var onModifiersDown: () -> Void = {}
    /// Set while Settings records a new shortcut, so the old one doesn't fire.
    var paused = false
    private var modifiersHeld = false

    private var tap: CFMachPort?

    private enum Key {
        static let tab: Int64 = 48
        static let escape: Int64 = 53
        static let returnKey: Int64 = 36
        static let enter: Int64 = 76
        static let left: Int64 = 123
        static let right: Int64 = 124
        static let down: Int64 = 125
        static let up: Int64 = 126
    }

    /// Returns false until Accessibility has been granted.
    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: hotKeyCallback,
            userInfo: nil
        ) else { return false }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }

        if paused { return pass }

        let flags = event.flags
        let held = flags.intersection(Shortcut.holdable)
        let shortcut = Shortcut.current
        let active = isActive()

        switch type {
        case .flagsChanged:
            let down = !shortcut.modifiers.isEmpty && held.isSuperset(of: shortcut.modifiers)
            if down && !modifiersHeld && !active {
                onModifiersDown()
            }
            modifiersHeld = down
            if active && !down {
                onCommit()
            }
            return pass

        case .keyDown:
            let code = event.getIntegerValueField(.keyboardEventKeycode)

            if code == shortcut.keyCode && held == shortcut.modifiers {
                let backwards = flags.contains(.maskShift)
                if active {
                    onStep(backwards ? -1 : 1)
                } else {
                    onOpen(backwards)
                }
                return nil
            }

            guard active else { return pass }
            switch code {
            case Key.escape: onCancel()
            case Key.returnKey, Key.enter: onCommit()
            case Key.left, Key.up: onStep(-1)
            case Key.right, Key.down, Key.tab, shortcut.keyCode: onStep(1)
            default: break
            }
            return nil

        case .keyUp:
            return active ? nil : pass

        default:
            return pass
        }
    }
}

private let hotKeyCallback: CGEventTapCallBack = { _, type, event, _ in
    HotKeys.shared.handle(type, event)
}
