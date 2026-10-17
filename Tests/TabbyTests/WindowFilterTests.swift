import CoreGraphics
import Foundation
import Testing
@testable import Tabby

@Suite("Full-screen window filter")
struct WindowFilterTests {
    private func info(id: CGWindowID = 42, pid: pid_t = 100, layer: Int = 0, alpha: Double = 1,
                      width: CGFloat = 1920, height: CGFloat = 1080) -> [String: Any] {
        [
            kCGWindowNumber as String: id,
            kCGWindowOwnerPID as String: pid,
            kCGWindowLayer as String: layer,
            kCGWindowAlpha as String: alpha,
            kCGWindowBounds as String: CGRect(x: 0, y: 0, width: width, height: height).dictionaryRepresentation,
        ]
    }

    @Test func fullScreenAppWindowCounts() {
        #expect(WindowSource.isAppWindow(info(), appPIDs: [100], excluding: []))
    }

    @Test func alreadyListedWindowIsSkipped() {
        #expect(!WindowSource.isAppWindow(info(id: 42), appPIDs: [100], excluding: [42]))
    }

    @Test func windowOfABackgroundProcessIsSkipped() {
        #expect(!WindowSource.isAppWindow(info(pid: 999), appPIDs: [100], excluding: []))
    }

    @Test("Menu bar items, panels and overlays sit above layer 0")
    func nonNormalLayerIsSkipped() {
        #expect(!WindowSource.isAppWindow(info(layer: 25), appPIDs: [100], excluding: []))
    }

    @Test func invisibleWindowIsSkipped() {
        #expect(!WindowSource.isAppWindow(info(alpha: 0), appPIDs: [100], excluding: []))
    }

    @Test("Tiny helper windows are skipped", arguments: [(CGFloat(1), CGFloat(1)), (120, 900), (900, 100)])
    func tinyWindowIsSkipped(width: CGFloat, height: CGFloat) {
        #expect(!WindowSource.isAppWindow(info(width: width, height: height), appPIDs: [100], excluding: []))
    }
}
