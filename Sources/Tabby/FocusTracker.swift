import Cocoa
import ApplicationServices

/// Remembers the order windows were last focused in, so the switcher can list them most recently used first.
/// Fed by Accessibility "focused window changed" notifications from every app, app activations
/// (Dock, ⌘Tab, clicks), and Tabby's own switches. Main thread only.
final class FocusTracker {
    static let shared = FocusTracker()

    /// Higher = used more recently.
    private(set) var recency: [CGWindowID: UInt64] = [:]
    private var counter: UInt64 = 0
    private var observers: [pid_t: AXObserver] = [:]
    private var started = false

    func mark(_ windowID: CGWindowID) {
        counter += 1
        recency[windowID] = counter
    }

    /// Call once Accessibility is granted.
    func start() {
        guard !started else { return }
        started = true

        // Until we've seen real focus changes, the current stacking order is the best guess.
        for windowID in WindowSource.onScreenWindowIDs().reversed() {
            mark(windowID)
        }

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            observe(app)
        }

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.observe(app)
            }
        }
        center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.forget(app.processIdentifier)
            }
        }
        center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.markFocusedWindow(of: app.processIdentifier)
            }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
            // Tabby's own Settings window (the switcher panel never becomes key).
            if let window = note.object as? NSWindow, window.windowNumber > 0 {
                self?.mark(CGWindowID(window.windowNumber))
            }
        }
    }

    private func observe(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard app.activationPolicy == .regular, pid != getpid(), observers[pid] == nil else { return }

        var observer: AXObserver?
        guard AXObserverCreate(pid, focusCallback, &observer) == .success, let observer else { return }
        let element = AXUIElementCreateApplication(pid)
        AXObserverAddNotification(observer, element, kAXFocusedWindowChangedNotification as CFString, nil)
        AXObserverAddNotification(observer, element, kAXMainWindowChangedNotification as CFString, nil)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    private func forget(_ pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    /// Asks the app which window has focus, off the main thread in case the app is slow to answer.
    private func markFocusedWindow(of pid: pid_t) {
        guard pid != getpid() else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let app = AXUIElementCreateApplication(pid)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
                  let value, CFGetTypeID(value) == AXUIElementGetTypeID(),
                  let windowID = WindowSource.windowID(of: value as! AXUIElement)
            else { return }
            DispatchQueue.main.async { FocusTracker.shared.mark(windowID) }
        }
    }

    fileprivate func focusChanged(_ element: AXUIElement) {
        // The notification's element is the window itself.
        if let windowID = WindowSource.windowID(of: element) {
            mark(windowID)
        }
    }
}

private let focusCallback: AXObserverCallback = { _, element, _, _ in
    FocusTracker.shared.focusChanged(element)
}
