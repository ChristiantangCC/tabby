import CoreGraphics
import SwiftUI
import Testing
@testable import Tabby

@Suite("Preferences")
struct PrefsTests {
    @Test func defaultShortcutIsOptionTab() {
        #expect(Shortcut.standard.keyCode == 48)
        #expect(Shortcut.standard.modifiers == .maskAlternate)
        #expect(Shortcut.standard.display == ["⌥", "⇥"])
    }

    @Test("Modifiers are shown in macOS order: ⌃ ⌥ ⌘")
    func shortcutDisplayOrder() {
        let shortcut = Shortcut(keyCode: 50, modifiers: [.maskCommand, .maskControl, .maskAlternate], keyLabel: "`")
        #expect(shortcut.display == ["⌃", "⌥", "⌘", "`"])
    }

    @Test func instantSpeedHasNoAnimation() {
        #expect(SwitchSpeed.instant.spring(0.3, 0.8) == nil)
        #expect(SwitchSpeed.instant.showDelay == 0)
        #expect(SwitchSpeed.fast.spring(0.3, 0.8) != nil)
    }

    @Test("Each speed step is slower than the one before")
    func speedsAreOrdered() {
        let speeds = SwitchSpeed.allCases
        for (faster, slower) in zip(speeds, speeds.dropFirst()) {
            #expect(faster.animationScale < slower.animationScale)
            #expect(faster.showDelay < slower.showDelay)
        }
    }

    @Test("Accent colours survive a round trip through hex", arguments: ["#0A84FF", "#FF375F", "#000000", "#FFFFFF"])
    func hexRoundTrip(hex: String) {
        #expect(Color(hex: hex).hex == hex)
    }

    @Test func badHexFallsBackToBlue() {
        #expect(Color(hex: "not a colour").hex == "#0A84FF")
    }
}
