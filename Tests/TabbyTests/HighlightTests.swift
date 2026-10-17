import AppKit
import Testing
@testable import Tabby

@Suite("Selected-window highlight")
struct HighlightTests {
    private let screen = CGSize(width: 1512, height: 982)

    private func model(frame: CGRect?, minimized: Bool = false, screenOrigin: CGPoint = .zero) -> SwitcherModel {
        let model = SwitcherModel()
        model.items = [WindowItem(
            id: 1, pid: 0, appName: "App", title: "", icon: NSImage(),
            element: nil, localWindow: nil, isMinimized: minimized, frame: frame
        )]
        model.screenOrigin = screenOrigin
        return model
    }

    @Test func windowOnThisScreenIsHighlightedInPlace() {
        let frame = CGRect(x: 100, y: 80, width: 800, height: 600)
        #expect(model(frame: frame).highlightFrame(in: screen) == frame)
    }

    @Test("A screen to the left of the main one is offset correctly")
    func secondScreenOffsets() {
        let model = model(frame: CGRect(x: -3340, y: -400, width: 1000, height: 700), screenOrigin: CGPoint(x: -3440, y: -458))
        #expect(model.highlightFrame(in: CGSize(width: 3440, height: 1440)) == CGRect(x: 100, y: 58, width: 1000, height: 700))
    }

    @Test func windowOnAnotherScreenIsNotHighlighted() {
        let frame = CGRect(x: 2000, y: 100, width: 800, height: 600)
        #expect(model(frame: frame).highlightFrame(in: screen) == nil)
    }

    @Test func minimizedWindowIsNotHighlighted() {
        let frame = CGRect(x: 100, y: 80, width: 800, height: 600)
        #expect(model(frame: frame, minimized: true).highlightFrame(in: screen) == nil)
    }

    @Test func windowWithoutFrameIsNotHighlighted() {
        #expect(model(frame: nil).highlightFrame(in: screen) == nil)
    }
}
