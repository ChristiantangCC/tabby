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
    typealias MainConnection = @convention(c) () -> Int32
    typealias CreateWithRemoteToken = @convention(c) (CFData) -> Unmanaged<AXUIElement>?
    typealias CopyDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    typealias CopySpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?

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
    static let mainConnection: MainConnection? = load("SLSMainConnectionID", skyLight)
    static let createWithRemoteToken: CreateWithRemoteToken? = load("_AXUIElementCreateWithRemoteToken", defaultHandle)
    static let copyDisplaySpaces: CopyDisplaySpaces? = load("SLSCopyManagedDisplaySpaces", skyLight)
    static let copySpacesForWindows: CopySpacesForWindows? = load("SLSCopySpacesForWindows", skyLight)
}

/// Full-screen windows live on their own Space, where Accessibility can't see them.
enum FullScreenSpaces {
    /// Space type the window server uses for a full-screen (or Split View) Space.
    private static let fullScreenType = 4
    /// All Spaces, not just the current one.
    private static let allSpacesMask: Int32 = 7

    /// Spaces whose windows Accessibility misses: every full-screen Space, plus, for a screen
    /// that's currently showing a full-screen Space, the desktop behind it (Accessibility only
    /// lists the Space on screen, so from inside full screen those windows would vanish).
    static func extraSpaceIDs() -> Set<Int> {
        guard let connection = Private.mainConnection?(),
              let displays = Private.copyDisplaySpaces?(connection)?.takeRetainedValue() as? [[String: Any]]
        else { return [] }
        return extraSpaceIDs(displays: displays)
    }

    /// The pure part of `extraSpaceIDs()`, fed the window server's display/Space description.
    static func extraSpaceIDs(displays: [[String: Any]]) -> Set<Int> {
        var ids = Set<Int>()
        for display in displays {
            let spaces = display["Spaces"] as? [[String: Any]] ?? []
            let fullScreen = spaces.filter { $0["type"] as? Int == fullScreenType }.compactMap { $0["ManagedSpaceID"] as? Int }
            ids.formUnion(fullScreen)

            let current = (display["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? Int
            if let current, fullScreen.contains(current) {
                ids.formUnion(spaces.filter { $0["type"] as? Int != fullScreenType }.compactMap { $0["ManagedSpaceID"] as? Int })
            }
        }
        return ids
    }

    static func spaces(of windowID: CGWindowID) -> Set<Int> {
        guard let connection = Private.mainConnection?(),
              let spaces = Private.copySpacesForWindows?(connection, allSpacesMask, [NSNumber(value: windowID)] as CFArray)?
                .takeRetainedValue() as? [Int]
        else { return [] }
        return Set(spaces)
    }
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

    /// Switchable windows on the current Space plus full-screen windows, most recently used first.
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

        let snapshot = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        // Accessibility sometimes still lists windows that are gone; keep only real ones.
        let existing = Set(snapshot.compactMap { $0[kCGWindowNumber as String] as? CGWindowID })
        items = items.filter { $0.localWindow != nil || existing.contains($0.id) }
        items += otherSpaceWindows(in: snapshot, excluding: Set(items.map(\.id)))

        let frames = windowFrames(in: snapshot)
        for index in items.indices {
            if let frame = frames[items[index].id] {
                items[index].frame = frame
                items[index].aspect = frame.width / frame.height
            }
        }

        return ordered(items, recency: FocusTracker.shared.recency, zOrder: zOrder())
    }

    /// Most recently used first. Windows Tabby hasn't seen focused yet follow in stacking order,
    /// and minimized windows go last.
    static func ordered(_ items: [WindowItem], recency: [CGWindowID: UInt64], zOrder: [CGWindowID: Int]) -> [WindowItem] {
        func rank(_ item: WindowItem) -> (Int, Int64) {
            if item.isMinimized { return (2, Int64(zOrder[item.id] ?? Int.max)) }
            if let used = recency[item.id] { return (0, -Int64(used)) }
            return (1, Int64(zOrder[item.id] ?? Int.max))
        }
        return items.enumerated()
            .sorted { lhs, rhs in
                let (a, b) = (rank(lhs.element), rank(rhs.element))
                return a != b ? a < b : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// The window-server ID behind an Accessibility window element.
    static func windowID(of element: AXUIElement) -> CGWindowID? {
        var windowID: CGWindowID = 0
        guard Private.getWindow?(element, &windowID) == .success, windowID != 0 else { return nil }
        return windowID
    }

    /// Normal app windows currently on screen, front to back.
    static func onScreenWindowIDs() -> [CGWindowID] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return list.compactMap { info in
            info[kCGWindowLayer as String] as? Int == 0 ? info[kCGWindowNumber as String] as? CGWindowID : nil
        }
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

    /// Windows on full-screen Spaces (and, from inside full screen, the desktop behind it),
    /// which the Accessibility listing misses.
    private static func otherSpaceWindows(in snapshot: [[String: Any]], excluding known: Set<CGWindowID>) -> [WindowItem] {
        let spaceIDs = FullScreenSpaces.extraSpaceIDs()
        guard !spaceIDs.isEmpty else { return [] }
        let me = getpid()
        let apps = Dictionary(
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular && $0.processIdentifier != me }
                .map { ($0.processIdentifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return snapshot.compactMap { info in
            guard isAppWindow(info, appPIDs: Set(apps.keys), excluding: known),
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let app = apps[pid],
                  !FullScreenSpaces.spaces(of: id).isDisjoint(with: spaceIDs)
            else { return nil }
            return WindowItem(
                id: id,
                pid: pid,
                appName: app.localizedName ?? "App",
                title: info[kCGWindowName as String] as? String ?? "",
                icon: app.icon ?? NSWorkspace.shared.icon(for: .application),
                element: nil,
                localWindow: nil,
                isMinimized: false
            )
        }
    }

    /// A normal, visible-sized window of a regular app that isn't listed yet.
    /// Filters out the menu bar items, tooltips and invisible helper windows apps also own.
    static func isAppWindow(_ info: [String: Any], appPIDs: Set<pid_t>, excluding known: Set<CGWindowID>) -> Bool {
        guard let id = info[kCGWindowNumber as String] as? CGWindowID, !known.contains(id),
              let pid = info[kCGWindowOwnerPID as String] as? pid_t, appPIDs.contains(pid),
              info[kCGWindowLayer as String] as? Int == 0,
              (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: bounds)
        else { return false }
        return rect.width >= 200 && rect.height >= 150
    }

    /// Brings a window to the front and gives it keyboard focus.
    static func focus(_ item: WindowItem) {
        if let window = item.localWindow {
            NSApp.activate(ignoringOtherApps: true)
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            return
        }
        // Windows on another Space (full screen) have no handle yet; without one macOS
        // brings the app forward but stays on the current Space.
        let element = item.element ?? remoteElement(forWindow: item.id, pid: item.pid)
        if item.isMinimized, let element {
            AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }

        var psn = ProcessSerialNumber()
        if let getPSN = Private.getPSN, let setFront = Private.setFront, getPSN(item.pid, &psn) == noErr {
            // 0x200 = user-generated activation, so macOS honours it from a background app.
            // Passing the window also moves to its Space, which is how full-screen windows come forward.
            _ = setFront(&psn, item.id, 0x200)
            makeKey(&psn, item.id)
        } else {
            NSRunningApplication(processIdentifier: item.pid)?.activate()
        }
        if let element {
            AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(element, kAXRaiseAction as CFString)
            if item.element == nil {
                bounceFullScreenIfNeeded(item, element: element)
            }
        }
    }

    /// Closes a window by pressing its own close button, so the app can still ask to save.
    static func close(_ item: WindowItem) {
        if let window = item.localWindow {
            window.performClose(nil)
            return
        }
        // Finding a full-screen window's handle can take a moment; keep it off the main thread.
        DispatchQueue.global(qos: .userInitiated).async {
            guard let element = item.element ?? remoteElement(forWindow: item.id, pid: item.pid) else { return }
            var button: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXCloseButtonAttribute as CFString, &button) == .success,
               let button, CFGetTypeID(button) == AXUIElementGetTypeID() {
                AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
            }
        }
    }

    /// macOS won't move to a full-screen Space while the same app has a window on the current
    /// Space. If the window still isn't showing shortly after the switch, take it out of full
    /// screen (it lands on this desktop), bring it forward, and put it back: entering full screen
    /// always moves you to it.
    private static func bounceFullScreenIfNeeded(_ item: WindowItem, element: AXUIElement) {
        let fullScreenAttribute = "AXFullScreen" as CFString
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.25) {
            var value: CFTypeRef?
            guard !isOnScreen(item.id),
                  AXUIElementCopyAttributeValue(element, fullScreenAttribute, &value) == .success,
                  value as? Bool == true
            else { return }

            AXUIElementSetAttributeValue(element, fullScreenAttribute, kCFBooleanFalse)
            waitUntil { isOnScreen(item.id) && !isFullScreen(element) }
            // Let the exit animation finish; a request made during it is silently ignored.
            usleep(500_000)
            AXUIElementPerformAction(element, kAXRaiseAction as CFString)
            for _ in 0..<3 where !isFullScreen(element) {
                AXUIElementSetAttributeValue(element, fullScreenAttribute, kCFBooleanTrue)
                waitUntil { isFullScreen(element) }
            }
        }
    }

    private static func isFullScreen(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, "AXFullScreen" as CFString, &value) == .success && value as? Bool == true
    }

    private static func isOnScreen(_ windowID: CGWindowID) -> Bool {
        onScreenWindowIDs().contains(windowID)
    }

    /// Polls for up to two seconds; full-screen animations take about 0.6 s.
    private static func waitUntil(_ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline && !condition() {
            usleep(50_000)
        }
    }

    /// Finds the Accessibility handle of a window on another Space, which the app's normal window
    /// list leaves out. Handles are built from a token (pid + "coco" + element number), so we try
    /// numbers until one matches (AltTab does the same). Chrome's full-screen window sat at #3824,
    /// so the search goes well past that; it stops at the first match and takes ~16 ms per 1,000.
    private static func remoteElement(forWindow windowID: CGWindowID, pid: pid_t) -> AXUIElement? {
        guard let create = Private.createWithRemoteToken else { return nil }
        var token = Data(count: 20)
        withUnsafeBytes(of: pid) { token.replaceSubrange(0..<4, with: $0) }
        withUnsafeBytes(of: Int32(0x636f_636f)) { token.replaceSubrange(8..<12, with: $0) }
        for elementID: UInt64 in 0..<50_000 {
            withUnsafeBytes(of: elementID) { token.replaceSubrange(12..<20, with: $0) }
            guard let element = create(token as CFData)?.takeRetainedValue() else { continue }
            if WindowSource.windowID(of: element) == windowID {
                return element
            }
        }
        return nil
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
    private static func windowFrames(in snapshot: [[String: Any]]) -> [CGWindowID: CGRect] {
        var frames: [CGWindowID: CGRect] = [:]
        for info in snapshot {
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
