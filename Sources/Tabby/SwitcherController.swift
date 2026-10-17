import Cocoa
import SwiftUI

final class SwitcherModel: ObservableObject {
    @Published var items: [WindowItem] = []
    @Published var selected = 0
    /// Continuous selection counter (never wraps) so circular layouts spin the short way round.
    @Published var spin: Double = 0
    @Published var thumbs: [CGWindowID: NSImage] = [:]
    @Published var appeared = false
    /// Top-left of the screen the overlay is on, in window-server coordinates.
    @Published var screenOrigin: CGPoint = .zero

    var current: WindowItem? { items.indices.contains(selected) ? items[selected] : nil }

    /// The selected window's frame inside the overlay, or nil if it isn't on this screen.
    func highlightFrame(in bounds: CGSize) -> CGRect? {
        guard let item = current, !item.isMinimized, let frame = item.frame else { return nil }
        let local = frame.offsetBy(dx: -screenOrigin.x, dy: -screenOrigin.y)
        let visible = local.intersection(CGRect(origin: .zero, size: bounds))
        // Mostly off this screen: an outline of a sliver would just be confusing.
        guard !visible.isNull, visible.width * visible.height > local.width * local.height * 0.5 else { return nil }
        return local
    }

    func step(_ delta: Int) {
        let count = items.count
        guard count > 0 else { return }
        selected = ((selected + delta) % count + count) % count
        spin += Double(delta)
    }

    func select(_ index: Int) {
        let count = items.count
        guard items.indices.contains(index) else { return }
        var delta = index - selected
        if delta > count / 2 { delta -= count }
        if delta < -count / 2 { delta += count }
        selected = index
        spin += Double(delta)
    }
}

/// Owns the overlay panel and the open → cycle → commit lifecycle.
final class SwitcherController {
    let model = SwitcherModel()
    private(set) var isActive = false
    private var isPreview = false
    private var pendingShow: DispatchWorkItem?
    private var pendingThumbs: [CGWindowID: NSImage] = [:]
    private var flushScheduled = false

    /// Tabby's own windows that should be switchable (the Settings window).
    var localWindows: () -> [NSWindow] = { [] }

    private lazy var panel: NSPanel = {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let root = SwitcherRoot(
            model: model,
            onPick: { [weak self] index in
                self?.model.select(index)
                self?.commit()
            },
            onDismiss: { [weak self] in self?.cancel() }
        )
        let host = NSHostingView(rootView: root)
        // Keep the panel exactly screen-sized; don't let SwiftUI resize it.
        host.sizingOptions = []
        host.wantsLayer = true
        host.layer?.backgroundColor = .clear
        panel.contentView = host
        return panel
    }()

    func open(backwards: Bool, preview: Bool = false) {
        if isActive { return }
        let items = WindowSource.current(local: localWindows())
        guard !items.isEmpty else { return }

        isActive = true
        isPreview = preview
        let ids = Set(items.map(\.id))
        Thumbnailer.shared.prune(keeping: ids)

        model.appeared = false
        model.items = items
        model.thumbs = Thumbnailer.shared.cache
        model.selected = items.count > 1 ? (backwards ? items.count - 1 : 1) : 0
        model.spin = Double(model.selected)

        Thumbnailer.shared.capture(items.filter { !$0.isMinimized }.map(\.id), maxSide: captureSize()) { [weak self] id, image in
            self?.queueThumb(id, image)
        }

        // A quick ⌥Tab tap switches without flashing the overlay.
        let work = DispatchWorkItem { [weak self] in self?.show() }
        pendingShow = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (preview ? 0 : SwitchSpeed.current.showDelay), execute: work)
    }

    func prewarm() {
        WindowSource.prefetch()
        Thumbnailer.shared.prewarm()
    }

    /// Batches incoming pictures into one redraw instead of one per window.
    private func queueThumb(_ id: CGWindowID, _ image: NSImage) {
        guard isActive else { return }
        pendingThumbs[id] = image
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            guard let self else { return }
            self.flushScheduled = false
            if self.isActive {
                self.model.thumbs.merge(self.pendingThumbs) { $1 }
            }
            self.pendingThumbs = [:]
        }
    }

    /// Pixel budget per picture: small tiles don't need 4K captures.
    private func captureSize() -> CGFloat {
        let layout = LayoutStyle(rawValue: UserDefaults.standard.string(forKey: Prefs.layout) ?? "") ?? .grid
        let size = UserDefaults.standard.object(forKey: Prefs.size) as? Double ?? 1
        switch layout {
        case .grid, .deck, .orbit: return 560 * size
        case .coverFlow: return 820 * size
        case .spotlight, .timeMachine: return 1500
        }
    }

    /// Shows fake windows inside a fixed rect, for README screenshots.
    func showDemo(items: [WindowItem], thumbs: [CGWindowID: NSImage], in rect: NSRect, selected: Int, screenOrigin: CGPoint) {
        isActive = true
        isPreview = true
        model.appeared = false
        model.items = items
        model.thumbs = thumbs
        model.selected = selected
        model.spin = Double(selected)
        model.screenOrigin = screenOrigin
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 11)
        panel.appearance = Prefs.currentAppearance.nsAppearance
        panel.setFrame(rect, display: false)
        panel.orderFrontRegardless()
        model.appeared = true
    }

    func step(_ delta: Int) {
        guard isActive else { return }
        model.step(delta)
    }

    func commit() {
        guard isActive, let item = model.current else { return close() }
        let preview = isPreview
        close()
        if !preview {
            WindowSource.focus(item)
        }
    }

    func cancel() {
        close()
    }

    private func show() {
        guard isActive else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }

        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        model.screenOrigin = CGPoint(x: screen.frame.minX, y: primaryHeight - screen.frame.maxY)
        panel.appearance = Prefs.currentAppearance.nsAppearance
        panel.setFrame(screen.frame, display: false)
        panel.orderFrontRegardless()
        withAnimation(SwitchSpeed.current.spring(0.32, 0.86)) {
            model.appeared = true
        }
    }

    private func close() {
        isActive = false
        pendingShow?.cancel()
        pendingShow = nil
        panel.orderOut(nil)
        model.appeared = false
    }
}
