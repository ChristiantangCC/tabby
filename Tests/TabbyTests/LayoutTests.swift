import AppKit
import SwiftUI
import Testing
@testable import Tabby

@Suite("Thumbnails layout")
struct LayoutTests {
    @Test func rowsWrapWhenFull() {
        #expect(FlowRows.rowCount(widths: [], spacing: 8, maxWidth: 500) == 0)
        #expect(FlowRows.rowCount(widths: [100, 100, 100], spacing: 8, maxWidth: 500) == 1)
        #expect(FlowRows.rowCount(widths: [200, 200, 200], spacing: 8, maxWidth: 500) == 2)
        // A tile wider than the row still gets a row of its own.
        #expect(FlowRows.rowCount(widths: [600, 100], spacing: 8, maxWidth: 500) == 2)
    }

    @Test("Tiles keep the window's shape, within limits", arguments: [
        (1.6, 224.0),  // normal window: height 140 × 1.6
        (0.2, 84.0),   // very tall window is clamped to 0.6
        (5.0, 336.0),  // ultrawide window is clamped to 2.4
    ])
    func tileWidthFollowsAspect(aspect: Double, expectedWidth: Double) {
        let theme = Theme(accent: .blue, size: 1, surface: .glass, showTitles: true, speed: .fast)
        let item = WindowItem(
            id: 1, pid: 0, appName: "App", title: "", icon: NSImage(),
            element: nil, localWindow: nil, isMinimized: false, aspect: CGFloat(aspect)
        )
        let size = GridLayout.thumbSize(item, theme)
        #expect(abs(size.height - 140) < 0.001)
        #expect(abs(size.width - CGFloat(expectedWidth)) < 0.001)
    }
}
