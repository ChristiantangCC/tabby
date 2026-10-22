import AppKit
import Testing
@testable import Tabby

@Suite("Switcher selection")
struct SwitcherModelTests {
    private func model(count: Int, selected: Int = 0) -> SwitcherModel {
        let model = SwitcherModel()
        model.items = (0..<count).map { index in
            WindowItem(
                id: CGWindowID(index + 1), pid: 0, appName: "App \(index)", title: "",
                icon: NSImage(), element: nil, localWindow: nil, isMinimized: false
            )
        }
        model.selected = selected
        model.spin = Double(selected)
        return model
    }

    @Test func stepWrapsForwards() {
        let model = model(count: 3, selected: 2)
        model.step(1)
        #expect(model.selected == 0)
        #expect(model.spin == 3)
    }

    @Test func stepWrapsBackwards() {
        let model = model(count: 3, selected: 0)
        model.step(-1)
        #expect(model.selected == 2)
        #expect(model.spin == -1)
    }

    @Test func stepWithNoWindowsDoesNothing() {
        let model = model(count: 0)
        model.step(1)
        #expect(model.selected == 0)
        #expect(model.current == nil)
    }

    @Test("Clicking a window spins the short way round the circle")
    func selectTakesShortestPath() {
        let model = model(count: 8, selected: 1)
        model.select(7)
        #expect(model.selected == 7)
        #expect(model.spin == -1)
    }

    @Test func selectIgnoresOutOfRange() {
        let model = model(count: 3, selected: 1)
        model.select(9)
        #expect(model.selected == 1)
    }

    @Test("Closing a window before the selection keeps the same window selected")
    func removeBeforeSelection() {
        let model = model(count: 4, selected: 2)
        model.remove(1)
        #expect(model.items.count == 3)
        #expect(model.current?.id == 3)
    }

    @Test("Closing the selected window selects the next one")
    func removeSelected() {
        let model = model(count: 4, selected: 1)
        model.remove(2)
        #expect(model.current?.id == 3)
    }

    @Test("Closing the selected last window selects the new last one")
    func removeSelectedLast() {
        let model = model(count: 3, selected: 2)
        model.remove(3)
        #expect(model.current?.id == 2)
    }
}
