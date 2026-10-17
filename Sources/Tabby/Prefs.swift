import SwiftUI

enum LayoutStyle: String, CaseIterable, Identifiable {
    case grid, coverFlow, deck, orbit, spotlight, timeMachine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grid: "Thumbnails"
        case .coverFlow: "Cover Flow"
        case .deck: "Deck"
        case .orbit: "Orbit"
        case .spotlight: "Spotlight"
        case .timeMachine: "Time Machine"
        }
    }

    var subtitle: String {
        switch self {
        case .grid: "Classic grid of live pictures"
        case .coverFlow: "3D shelf that flips past"
        case .deck: "A hand of cards, fanned out"
        case .orbit: "Windows circle a big preview"
        case .spotlight: "One huge preview, tiny strip"
        case .timeMachine: "Windows stacked into the past"
        }
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

enum SurfaceStyle: String, CaseIterable, Identifiable {
    case glass, solid, frameless

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum SwitchSpeed: String, CaseIterable, Identifiable {
    case instant, fast, normal, relaxed

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// Multiplier on every switcher animation; 0 means no animation at all.
    var animationScale: Double {
        switch self {
        case .instant: 0
        case .fast: 0.45
        case .normal: 1
        case .relaxed: 1.6
        }
    }

    /// How long ⌥Tab must be held before the overlay appears (a quick tap just switches).
    var showDelay: Double {
        switch self {
        case .instant: 0
        case .fast: 0.03
        case .normal: 0.08
        case .relaxed: 0.15
        }
    }

    func spring(_ response: Double, _ damping: Double) -> Animation? {
        animationScale == 0 ? nil : .spring(response: response * animationScale, dampingFraction: damping)
    }

    static var current: SwitchSpeed {
        SwitchSpeed(rawValue: UserDefaults.standard.string(forKey: Prefs.speed) ?? "") ?? .fast
    }
}

/// The one switcher shortcut: hold the modifiers, tap the key to cycle, release to switch.
struct Shortcut: Equatable {
    var keyCode: Int64
    var modifiers: CGEventFlags
    var keyLabel: String

    /// Modifiers that can be "held"; Shift is reserved for cycling backwards.
    static let holdable: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
    static let standard = Shortcut(keyCode: 48, modifiers: .maskAlternate, keyLabel: "⇥")

    static var current: Shortcut {
        let defaults = UserDefaults.standard
        guard let label = defaults.string(forKey: Prefs.shortcutLabel) else { return .standard }
        return Shortcut(
            keyCode: Int64(defaults.integer(forKey: Prefs.shortcutKey)),
            modifiers: CGEventFlags(rawValue: UInt64(defaults.integer(forKey: Prefs.shortcutModifiers))),
            keyLabel: label
        )
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(Int(keyCode), forKey: Prefs.shortcutKey)
        defaults.set(Int(modifiers.rawValue), forKey: Prefs.shortcutModifiers)
        defaults.set(keyLabel, forKey: Prefs.shortcutLabel)
    }

    /// Key caps in the standard macOS order: ⌃ ⌥ ⌘ then the key.
    var display: [String] {
        var caps: [String] = []
        if modifiers.contains(.maskControl) { caps.append("⌃") }
        if modifiers.contains(.maskAlternate) { caps.append("⌥") }
        if modifiers.contains(.maskCommand) { caps.append("⌘") }
        return caps + [keyLabel]
    }
}

enum Prefs {
    static let checkUpdates = "checkForUpdates"
    static let shortcutKey = "shortcutKeyCode"
    static let shortcutModifiers = "shortcutModifiers"
    static let shortcutLabel = "shortcutLabel"
    static let speed = "speed"
    static let layout = "layout"
    static let appearance = "appearance"
    static let surface = "surface"
    static let accent = "accent"
    static let size = "size"
    static let dim = "dimBackdrop"
    static let titles = "showTitles"

    static let accentPresets: [(name: String, hex: String)] = [
        ("Blue", "#0A84FF"), ("Indigo", "#5E5CE6"), ("Purple", "#BF5AF2"), ("Pink", "#FF375F"),
        ("Orange", "#FF9F0A"), ("Yellow", "#FFD60A"), ("Green", "#30D158"), ("Mint", "#63E6E2"),
        ("Graphite", "#98989D"),
    ]

    static var currentAppearance: AppearanceMode {
        AppearanceMode(rawValue: UserDefaults.standard.string(forKey: Prefs.appearance) ?? "") ?? .system
    }
}

/// Everything a layout needs to draw itself.
struct Theme {
    var accent: Color
    var size: Double
    var surface: SurfaceStyle
    var showTitles: Bool
    var speed: SwitchSpeed

    /// Base thumbnail box for grid-like layouts.
    var thumb: CGSize { CGSize(width: 220 * size, height: 140 * size) }

    func scaled(by factor: Double) -> Theme {
        var copy = self
        copy.size *= factor
        return copy
    }
}

extension Color {
    init(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        let value = UInt64(digits, radix: 16) ?? 0x0A84FF
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    var hex: String {
        let color = NSColor(self).usingColorSpace(.sRGB) ?? .systemBlue
        return String(
            format: "#%02X%02X%02X",
            Int((color.redComponent * 255).rounded()),
            Int((color.greenComponent * 255).rounded()),
            Int((color.blueComponent * 255).rounded())
        )
    }
}
