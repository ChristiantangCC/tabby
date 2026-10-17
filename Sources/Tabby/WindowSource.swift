import Cocoa
import ApplicationServices

/// One switchable window.
struct WindowItem: Identifiable, Equatable {
    let id: CGWindowID
    let pid: pid_t
    let appName: String
    let title: String
    let icon: NSImage
    /// Another app's window, driven through Accessibility.
    let element: AXUIElement?
    /// One of Tabby's own windows (AX can't query our own process from the main thread).
    let localWindow: NSWindow?
    let isMinimized: Bool
    /// Width ÷ height of the real window, so tiles can take its shape.
    var aspect: CGFloat = 1.6
    /// Where the window really is, in window-server coordinates (origin top-left of the main display).
    var frame: CGRect?

    var displayTitle: String { title.isEmpty ? appName : title }

    static func == (lhs: WindowItem, rhs: WindowItem) -> Bool { lhs.id == rhs.id }
}

/// Private macOS calls, resolved at runtime so nothing links against private frameworks.
private enum Private {
    typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    typealias SetFront = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError
    typealias PostEvent = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError
    typealias GetPSN = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

    private static let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)
    private static let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    private static func load<T>(_ name: String, _ handle: UnsafeMutableRawPointer?) -> T? {
        guard let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }

    static let getWindow: GetWindow? = load("_AXUIElementGetWindow", defaultHandle)
    static let setFront: SetFront? = load("_SLPSSetFrontProcessWithOptions", skyLight)
    static let postEvent: PostEvent? = load("SLPSPostEventRecordTo", skyLight)
    static let getPSN: GetPSN? = load("GetProcessForPID", defaultHandle)
}

enum WindowSource {
    private static let configureTimeout: Void = {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.2)
    }()

    private static let cacheLock = NSLock()
    private static var cached: (items: [WindowItem], at: CFTimeInterval)?

    /// Starts listing other apps' windows in the background (called when ⌥ goes down).
    static func prefetch() {
        DispatchQueue.global(qos: .userInteractive).async {
            let items = otherAppWindows()
            cacheLock.lock()
            cached = (items, CACurrentMediaTime())
            cacheLock.unlock()
        }
    }

    /// Switchable windows on the current Space, most recently used first.
    static func current(local: [NSWindow] = []) -> [WindowItem] {
        let me = getpid()
        var items: [WindowItem] = local.map { window in
            WindowItem(
                id: CGWindowID(window.windowNumber),
                pid: me,
                appName: "Tabby",
                title: "Settings",
                icon: NSApp.applicationIconImage,
                element: nil,
                localWindow: window,
                isMinimized: window.isMiniaturized,
                aspect: window.frame.height > 0 ? window.frame.width / window.frame.height : 1.6,
                frame: CGRect(
                    x: window.frame.minX,
                    y: (NSScreen.screens.first?.frame.height ?? 0) - window.frame.maxY,
                    width: window.frame.width,
                    height: window.frame.height
                )
            )
        }

        cacheLock.lock()
        let fresh = cached.flatMap { CACurrentMediaTime() - $0.at < 1.0 ? $0.items : nil }
        cached = nil
        cacheLock.unlock()
        items += fresh ?? otherAppWindows()

        let frames = windowFrames()
        for index in items.indices {
            if let frame = frames[items[index].id] {
                items[index].frame = frame
                items[index].aspect = frame.width / frame.height
            }
        }

        let order = zOrder()
        let rank = { (item: WindowItem) -> Int in
            order[item.id] ?? (item.isMinimized ? 2_000_000 : 1_000_000)
        }
        return items.sorted { rank($0) < rank($1) }
    }

    /// Asks every app for its windows in parallel, so one slow app doesn't hold up the rest.
    private static func otherAppWindows() -> [WindowItem] {
        _ = configureTimeout
        let me = getpid()
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != me && !$0.isTerminated
        }
        var results = [[WindowItem]](repeating: [], count: apps.count)
        results.withUnsafeMutableBufferPointer { buffer in
            DispatchQueue.concurrentPerform(iterations: apps.count) { index in
                buffer[index] = windows(of: apps[index])
            }
        }
        return results.flatMap { $0 }
    }

    private static func windows(of app: NSRunningApplication) -> [WindowItem] {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let windows: [AXUIElement] = attribute(axApp, kAXWindowsAttribute) else { return [] }
        let icon = app.icon ?? NSWorkspace.shared.icon(for: .application)

        return windows.compactMap { window in
            let subrole: String? = attribute(window, kAXSubroleAttribute)
            guard subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole else { return nil }
            var windowID: CGWindowID = 0
            guard Private.getWindow?(window, &windowID) == .success, windowID != 0 else { return nil }
            return WindowItem(
                id: windowID,
                pid: app.processIdentifier,
                appName: app.localizedName ?? "App",
                title: attribute(window, kAXTitleAttribute) ?? "",
                icon: icon,
                element: window,
                localWindow: nil,
                isMinimized: attribute(window, kAXMinimizedAttribute) ?? false
            )
        }
    }

    /// Brings a window to the front and gives it keyboard focus.
    static func focus(_ item: WindowItem) {
        if let window = item.localWindow {
            NSApp.activate(ignoringOtherApps: true)
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            return
        }
        guard let element = item.element else { return }
        if item.isMinimized {
            AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }

        var psn = ProcessSerialNumber()
        if let getPSN = Private.getPSN, let setFront = Private.setFront, getPSN(item.pid, &psn) == noErr {
            // 0x200 = user-generated activation, so macOS honours it from a background app.
            _ = setFront(&psn, item.id, 0x200)
            makeKey(&psn, item.id)
        } else {
            NSRunningApplication(processIdentifier: item.pid)?.activate()
        }
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    /// Window-server event pair that makes one specific window key (same trick as yabai/AltTab).
    private static func makeKey(_ psn: inout ProcessSerialNumber, _ windowID: CGWindowID) {
        guard let post = Private.postEvent else { return }
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xf8
        bytes[0x3a] = 0x10
        withUnsafeBytes(of: windowID) { raw in
            for i in 0..<4 { bytes[0x3c + i] = raw[i] }
        }
        for i in 0x20..<0x30 { bytes[i] = 0xff }
        bytes[0x08] = 0x01
        _ = post(&psn, &bytes)
        bytes[0x08] = 0x02
        _ = post(&psn, &bytes)
    }

    /// Position and size of every window, minimized and off-screen ones included.
    private static func windowFrames() -> [CGWindowID: CGRect] {
        let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        var frames: [CGWindowID: CGRect] = [:]
        for info in list {
            guard let number = info[kCGWindowNumber as String] as? CGWindowID,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dict),
                  rect.height > 0 else { continue }
            frames[number] = rect
        }
        return frames
    }

    /// Front-to-back position of every on-screen window.
    private static func zOrder() -> [CGWindowID: Int] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        var order: [CGWindowID: Int] = [:]
        for (index, info) in list.enumerated() {
            if let number = info[kCGWindowNumber as String] as? CGWindowID {
                order[number] = index
            }
        }
        return order
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
