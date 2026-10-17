import AppKit
import Testing
@testable import Tabby

@Suite("Most recently used order")
struct OrderingTests {
    private func window(_ id: CGWindowID, minimized: Bool = false) -> WindowItem {
        WindowItem(id: id, pid: 0, appName: "App \(id)", title: "", icon: NSImage(),
                   element: nil, localWindow: nil, isMinimized: minimized)
    }

    private func ids(_ items: [WindowItem]) -> [CGWindowID] { items.map(\.id) }

    @Test func lastUsedComesFirst() {
        let items = [window(1), window(2), window(3)]
        let sorted = WindowSource.ordered(items, recency: [1: 5, 2: 9, 3: 7], zOrder: [1: 0, 2: 1, 3: 2])
        #expect(ids(sorted) == [2, 3, 1])
    }

    @Test("Recency beats stacking order, e.g. a window on another screen used a moment ago")
    func recencyBeatsStacking() {
        let items = [window(1), window(2)]
        let sorted = WindowSource.ordered(items, recency: [2: 3], zOrder: [1: 0, 2: 5])
        #expect(ids(sorted) == [2, 1])
    }

    @Test func unseenWindowsFollowInStackingOrder() {
        let items = [window(1), window(2), window(3)]
        let sorted = WindowSource.ordered(items, recency: [3: 1], zOrder: [1: 4, 2: 2])
        #expect(ids(sorted) == [3, 2, 1])
    }

    @Test func minimizedWindowsGoLast() {
        let items = [window(1, minimized: true), window(2), window(3)]
        let sorted = WindowSource.ordered(items, recency: [1: 99, 2: 1], zOrder: [3: 0])
        #expect(ids(sorted) == [2, 3, 1])
    }

    @Test func tabbyRemembersWhatItSwitchedTo() {
        let tracker = FocusTracker()
        tracker.mark(10)
        tracker.mark(20)
        tracker.mark(10)
        #expect(tracker.recency[10]! > tracker.recency[20]!)
    }
}
