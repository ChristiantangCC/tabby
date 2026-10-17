import Cocoa
import SwiftUI
import ScreenCaptureKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private let switcher = SwitcherController()
    private var settingsWindow: NSWindow?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if DemoMode.isOn {
            MainActor.assumeIsolated { startDemo() }
            return
        }
        setUpStatusItem()
        wireHotKeys()
        startHotKeysWhenTrusted()

        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
            // Recent macOS only lists an app under Screen Recording once it actually asks ScreenCaptureKit.
            Task { _ = try? await SCShareableContent.current }
        }
        if !AXIsProcessTrusted() || !CGPreflightScreenCaptureAccess() {
            showSettings()
        }
        if CommandLine.arguments.contains("--preview") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.switcher.open(backwards: false, preview: true)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    /// Wallpaper window + switcher with fake apps, centred on the main screen.
    /// Prints the rect in `screencapture -R` coordinates so a script can grab exactly that area.
    private var demoWindow: NSWindow?

    @MainActor
    private func startDemo() {
        guard let screen = NSScreen.main else { return }
        let size = DemoMode.canvas
        let rect = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        let window = NSWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)
        window.contentView = NSHostingView(rootView: DemoWallpaper())
        window.orderFrontRegardless()
        demoWindow = window

        let selected = Int(UserDefaults.standard.string(forKey: "demoSelected") ?? "") ?? 1
        switcher.showDemo(items: DemoMode.items(), thumbs: DemoMode.thumbnails(), in: rect, selected: selected)

        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        print("RECT \(Int(rect.minX)),\(Int(primaryHeight - rect.maxY)),\(Int(rect.width)),\(Int(rect.height))")
        fflush(stdout)
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.stack.fill", accessibilityDescription: "Tabby")

        let menu = NSMenu()
        menu.addItem(withTitle: "Preview Switcher", action: #selector(preview), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Tabby", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    private func wireHotKeys() {
        let keys = HotKeys.shared
        keys.isActive = { [unowned self] in switcher.isActive }
        keys.onOpen = { [unowned self] backwards in switcher.open(backwards: backwards) }
        keys.onStep = { [unowned self] delta in switcher.step(delta) }
        keys.onCommit = { [unowned self] in switcher.commit() }
        keys.onCancel = { [unowned self] in switcher.cancel() }
        keys.onModifiersDown = { [unowned self] in switcher.prewarm() }
        switcher.localWindows = { [weak self] in
            guard let window = self?.settingsWindow, window.isVisible || window.isMiniaturized else { return [] }
            return [window]
        }
    }

    private func startHotKeysWhenTrusted() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options), HotKeys.shared.start() { return }

        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            if AXIsProcessTrusted(), HotKeys.shared.start() {
                timer.invalidate()
                self?.permissionTimer = nil
            }
        }
    }

    @objc private func preview() {
        // Let the menu finish closing first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.switcher.open(backwards: false, preview: true)
        }
    }

    @objc private func openSettings() {
        showSettings()
    }

    private func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView(onPreview: { [weak self] in
                self?.switcher.open(backwards: false, preview: true)
            })
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            // An empty unified toolbar makes the titlebar taller, which moves the traffic
            // lights down and in so they sit inside the floating sidebar card.
            let toolbar = NSToolbar(identifier: "TabbySettings")
            toolbar.showsBaselineSeparator = false
            window.toolbar = toolbar
            window.toolbarStyle = .unified
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 940, height: 640))
            window.setFrameAutosaveName("TabbySettings")
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        // Show a Dock icon while Settings is open; back to menu-bar-only when it closes.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.title = "Tabby Settings"
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === settingsWindow else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}

