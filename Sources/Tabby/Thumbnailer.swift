import Cocoa
import ScreenCaptureKit

/// Captures window pictures with ScreenCaptureKit and keeps the last one per window,
/// so the switcher can show something instantly and swap in fresh pictures as they land.
/// One in-flight / recent SCShareableContent fetch, shared by prewarm and capture.
private actor ContentCache {
    private var task: Task<SCShareableContent, Error>?
    private var stamp = Date.distantPast

    func get(maxAge: TimeInterval = 1.5) async throws -> SCShareableContent {
        if let task, Date().timeIntervalSince(stamp) < maxAge {
            return try await task.value
        }
        let fresh = Task { try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) }
        task = fresh
        stamp = Date()
        return try await fresh.value
    }
}

final class Thumbnailer {
    static let shared = Thumbnailer()
    private let content = ContentCache()

    /// Called when ⌥ goes down, so the window list is already fetched by the time Tab lands.
    func prewarm() {
        guard CGPreflightScreenCaptureAccess() else { return }
        let content = self.content
        Task.detached(priority: .userInitiated) { _ = try? await content.get() }
    }

    /// Main thread only.
    private(set) var cache: [CGWindowID: NSImage] = [:]

    func prune(keeping ids: Set<CGWindowID>) {
        cache = cache.filter { ids.contains($0.key) }
    }

    func capture(_ ids: [CGWindowID], maxSide: CGFloat, deliver: @escaping (CGWindowID, NSImage) -> Void) {
        guard !ids.isEmpty, CGPreflightScreenCaptureAccess() else { return }
        let wanted = Set(ids)
        let cache = self.content

        Task.detached(priority: .userInitiated) {
            guard let content = try? await cache.get() else { return }
            let windows = content.windows.filter { wanted.contains($0.windowID) }

            await withTaskGroup(of: Void.self) { group in
                for window in windows {
                    group.addTask {
                        let size = window.frame.size
                        guard size.width > 1, size.height > 1 else { return }
                        // Only as many pixels as the layout will actually draw.
                        let factor = min(2, maxSide / max(size.width, size.height))

                        let config = SCStreamConfiguration()
                        config.width = Int(size.width * factor)
                        config.height = Int(size.height * factor)
                        config.showsCursor = false
                        config.ignoreShadowsSingleWindow = true
                        config.captureResolution = .best

                        let filter = SCContentFilter(desktopIndependentWindow: window)
                        guard let cgImage = try? await SCScreenshotManager.captureImage(
                            contentFilter: filter, configuration: config
                        ) else { return }

                        let image = NSImage(cgImage: cgImage, size: size)
                        let id = window.windowID
                        await MainActor.run {
                            self.cache[id] = image
                            deliver(id, image)
                        }
                    }
                }
            }
        }
    }
}
