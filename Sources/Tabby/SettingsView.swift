import SwiftUI
import ServiceManagement
import ScreenCaptureKit

enum SettingsPage: String, CaseIterable, Identifiable {
    case layout, appearance, general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .layout: "Layout"
        case .appearance: "Appearance"
        case .general: "General"
        }
    }

    var subtitle: String {
        switch self {
        case .layout: "Pick how windows are arranged, and how big."
        case .appearance: "Theme, material and accent colour."
        case .general: "Permissions, startup and shortcuts."
        }
    }

    var symbol: String {
        switch self {
        case .layout: "square.grid.2x2"
        case .appearance: "paintpalette"
        case .general: "gearshape"
        }
    }
}

/// Size presets shown as a segmented control; the stored value stays a plain scale factor.
private enum SizePreset: Double, CaseIterable, Identifiable {
    case small = 0.8, medium = 1.0, large = 1.25, huge = 1.5

    var id: Double { rawValue }
    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .huge: "Huge"
        }
    }

    static func nearest(to value: Double) -> SizePreset {
        allCases.min { abs($0.rawValue - value) < abs($1.rawValue - value) } ?? .medium
    }
}

struct SettingsView: View {
    let onPreview: () -> Void

    @AppStorage(Prefs.layout) private var layout = LayoutStyle.grid
    @AppStorage(Prefs.appearance) private var appearance = AppearanceMode.system
    @AppStorage(Prefs.surface) private var surface = SurfaceStyle.glass
    @AppStorage(Prefs.accent) private var accentHex = "#0A84FF"
    @AppStorage(Prefs.size) private var size = 1.0
    @AppStorage(Prefs.dim) private var dim = true
    @AppStorage(Prefs.titles) private var showTitles = true
    @AppStorage(Prefs.speed) private var speed = SwitchSpeed.fast

    @AppStorage(Prefs.checkUpdates) private var checkUpdates = true
    @ObservedObject private var updates = UpdateChecker.shared

    @State private var page: SettingsPage = .layout
    @State private var accessibilityOK = AXIsProcessTrusted()
    @State private var screenOK = CGPreflightScreenCaptureAccess()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private let poll = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()
    private var accent: Color { Color(hex: accentHex) }
    private var permissionsMissing: Bool { !accessibilityOK || !screenOK }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            detail
        }
        .frame(minWidth: 880, minHeight: 600)
        .tint(accent)
        .preferredColorScheme(appearance == .system ? nil : (appearance == .dark ? .dark : .light))
        .onReceive(poll) { _ in
            accessibilityOK = AXIsProcessTrusted()
            screenOK = CGPreflightScreenCaptureAccess()
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 38, height: 38)
                Text("Tabby")
                    .font(.system(size: 18, weight: .bold))
            }
            .padding(.horizontal, 16)
            .padding(.top, 58)
            .padding(.bottom, 18)

            VStack(spacing: 2) {
                ForEach(SettingsPage.allCases) { item in
                    SidebarItem(
                        page: item,
                        selected: page == item,
                        warning: item == .general && permissionsMissing
                    )
                    .onTapGesture { page = item }
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            if let release = updates.available {
                UpdateCard(release: release, accent: accent)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
            }

            Button("Quit Tabby") { NSApp.terminate(nil) }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 18)
        }
        .frame(width: 210)
        .background(SidebarCard())
        // Floating card inset from the window edges; the traffic lights sit inside it.
        .padding(8)
        .ignoresSafeArea()
    }

    // MARK: Detail

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(page.title).font(.system(size: 20, weight: .semibold))
                        Text(page.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: onPreview) {
                        Label("Preview", systemImage: "play.fill")
                    }
                    .keyboardShortcut("p")
                    .help("Show the switcher with these settings (⌘P)")
                }

                if permissionsMissing && page != .general {
                    permissionBanner
                }

                switch page {
                case .layout: layoutPage
                case .appearance: appearancePage
                case .general: generalPage
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 2)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
    }

    private var permissionBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("Tabby is missing a permission, so it can't work yet.").font(.system(size: 13))
            Spacer()
            Button("Fix in General") { page = .general }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.orange.opacity(0.12)))
    }

    // MARK: Pages

    private var layoutPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(LayoutStyle.allCases) { style in
                    LayoutCard(style: style, selected: layout == style, accent: accent)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { layout = style }
                        }
                }
            }

            SettingsGroup {
                SettingRow("Size") {
                    Picker("", selection: Binding(
                        get: { SizePreset.nearest(to: size) },
                        set: { size = $0.rawValue }
                    )) {
                        ForEach(SizePreset.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 320)
                }
                RowDivider()
                SettingRow("Speed") {
                    Picker("", selection: $speed) {
                        ForEach(SwitchSpeed.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 320)
                }
                RowDivider()
                SettingRow("Show window titles") {
                    Toggle("", isOn: $showTitles).toggleStyle(.switch).labelsHidden()
                }
            }
        }
    }

    private var appearancePage: some View {
        SettingsGroup {
            SettingRow("Theme") {
                Picker("", selection: $appearance) {
                    Label("Light", systemImage: "sun.max").tag(AppearanceMode.light)
                    Label("Dark", systemImage: "moon").tag(AppearanceMode.dark)
                    Label("System", systemImage: "laptopcomputer").tag(AppearanceMode.system)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 320)
            }
            RowDivider()
            SettingRow("Surface") {
                Picker("", selection: $surface) {
                    ForEach(SurfaceStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 320)
            }
            RowDivider()
            SettingRow("Accent colour") {
                HStack(spacing: 7) {
                    ForEach(Prefs.accentPresets, id: \.hex) { preset in
                        Swatch(color: Color(hex: preset.hex), selected: accentHex.uppercased() == preset.hex)
                            .help(preset.name)
                            .onTapGesture { accentHex = preset.hex }
                    }
                    ColorPicker("", selection: Binding(get: { accent }, set: { accentHex = $0.hex }), supportsOpacity: false)
                        .labelsHidden()
                }
            }
            RowDivider()
            SettingRow("Dim the screen behind") {
                Toggle("", isOn: $dim).toggleStyle(.switch).labelsHidden()
            }
        }
    }

    private var generalPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsGroup(title: "Permissions") {
                PermissionRow(
                    title: "Accessibility",
                    detail: "Catch ⌥Tab and switch windows",
                    granted: accessibilityOK,
                    request: {
                        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                        _ = AXIsProcessTrustedWithOptions(options)
                        openPane("Privacy_Accessibility")
                    }
                )
                RowDivider()
                PermissionRow(
                    title: "Screen Recording",
                    detail: "Draw live window thumbnails",
                    granted: screenOK,
                    request: {
                        // Asking ScreenCaptureKit is what makes macOS show its alert and list the app.
                        _ = CGRequestScreenCaptureAccess()
                        Task { _ = try? await SCShareableContent.current }
                        openPane("Privacy_ScreenCapture")
                    }
                )
            }
            SettingsGroup(title: "Startup") {
                SettingRow("Launch at login") {
                    Toggle("", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .onChange(of: launchAtLogin) { _, enabled in
                            do {
                                if enabled {
                                    try SMAppService.mainApp.register()
                                } else {
                                    try SMAppService.mainApp.unregister()
                                }
                            } catch {
                                launchAtLogin = SMAppService.mainApp.status == .enabled
                            }
                        }
                }
            }
            SettingsGroup(title: "Updates") {
                SettingRow("Check for updates automatically") {
                    Toggle("", isOn: $checkUpdates)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .onChange(of: checkUpdates) { _, _ in updates.start() }
                }
                RowDivider()
                SettingRow("Tabby \(UpdateChecker.currentVersion)") {
                    if let release = updates.available {
                        Button("Download \(release.version)") { NSWorkspace.shared.open(release.url) }
                    } else {
                        Button("Check Now") { updates.check() }
                    }
                }
            }
            SettingsGroup(title: "Shortcut") {
                SettingRow("Open switcher") { ShortcutRecorder(accent: accent) }
            }
        }
    }
}

private struct SidebarItem: View {
    let page: SettingsPage
    let selected: Bool
    let warning: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: page.symbol)
                .font(.system(size: 15))
                .frame(width: 22)
            Text(page.title)
                .font(.system(size: 14))
            Spacer()
            if warning {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Color.primary.opacity(0.11) : .clear)
        )
        .contentShape(Rectangle())
    }
}

/// The sidebar's floating rounded panel: a shade darker than the page, with a hairline edge.
private struct SidebarCard: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        shape
            .fill(scheme == .dark ? Color.black.opacity(0.28) : Color.black.opacity(0.05))
            .overlay(shape.strokeBorder(Color.primary.opacity(scheme == .dark ? 0.1 : 0.08), lineWidth: 1))
            .shadow(color: .black.opacity(scheme == .dark ? 0.25 : 0.06), radius: 6, y: 2)
    }
}

/// Sidebar card shown while a newer release is out, like AltTab's upgrade card.
private struct UpdateCard: View {
    let release: UpdateChecker.Release
    let accent: Color

    var body: some View {
        Button { NSWorkspace.shared.open(release.url) } label: {
            VStack(spacing: 2) {
                Text("Update available")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.85))
                Text("Get Tabby \(release.version)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [accent, accent.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Rounded group of rows, like System Settings.
private struct SettingsGroup<Content: View>: View {
    var title: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            VStack(spacing: 0) { content }
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.045)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
        }
    }
}

private struct RowDivider: View {
    var body: some View {
        Divider().padding(.horizontal, 14)
    }
}

// MARK: - Pieces


private struct SettingRow<Control: View>: View {
    let title: String
    @ViewBuilder let control: Control

    init(_ title: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.control = control()
    }

    var body: some View {
        HStack {
            Text(title).font(.system(size: 13))
            Spacer()
            control
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
    }
}

private struct KeyCap: View {
    let label: String
    init(_ label: String) { self.label = label }

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(.primary.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.primary.opacity(0.15), lineWidth: 1))
    }
}

private struct Swatch: View {
    let color: Color
    let selected: Bool

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 20, height: 20)
            .overlay(Circle().strokeBorder(.white.opacity(selected ? 0.9 : 0), lineWidth: 2))
            .padding(2)
            .overlay(Circle().strokeBorder(color.opacity(selected ? 1 : 0), lineWidth: 2))
            .scaleEffect(selected ? 1.1 : 1)
            .animation(.spring(response: 0.25), value: selected)
            .contentShape(Circle())
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let request: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? .green : .orange)
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("Grant…", action: request)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct LayoutCard: View {
    let style: LayoutStyle
    let selected: Bool
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LayoutGlyph(style: style, accent: accent)
                .scaleEffect(1.45)
                .frame(height: 130)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.primary.opacity(0.05)))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(style.title).font(.system(size: 13, weight: .semibold))
                Text(style.subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
            }
            .padding(.horizontal, 2)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(selected ? accent.opacity(0.13) : .primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? accent : .primary.opacity(0.08), lineWidth: selected ? 2 : 1)
        )
        .scaleEffect(selected ? 1.0 : 0.98)
        .contentShape(Rectangle())
    }
}

/// Miniature drawing of each layout.
private struct LayoutGlyph: View {
    let style: LayoutStyle
    let accent: Color

    private func card(_ highlighted: Bool = false, _ w: CGFloat = 26, _ h: CGFloat = 17) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(highlighted ? accent : Color.primary.opacity(0.22))
            .frame(width: w, height: h)
            .shadow(color: highlighted ? accent.opacity(0.6) : .clear, radius: 4)
    }

    var body: some View {
        switch style {
        case .grid:
            VStack(spacing: 5) {
                HStack(spacing: 5) { card(); card(true); card() }
                HStack(spacing: 5) { card(); card(); card() }
            }
        case .coverFlow:
            HStack(spacing: -6) {
                ForEach(0..<2, id: \.self) { _ in
                    card(false, 22, 22).rotation3DEffect(.degrees(-60), axis: (0, 1, 0), perspective: 0.5)
                }
                card(true, 36, 26).zIndex(1)
                ForEach(0..<2, id: \.self) { _ in
                    card(false, 22, 22).rotation3DEffect(.degrees(60), axis: (0, 1, 0), perspective: 0.5)
                }
            }
        case .deck:
            ZStack {
                ForEach(0..<5, id: \.self) { i in
                    card(i == 2, 22, 30)
                        .offset(y: i == 2 ? -10 : 0)
                        .rotationEffect(.degrees(Double(i - 2) * 14), anchor: UnitPoint(x: 0.5, y: 2.2))
                }
            }
            .offset(y: 8)
        case .orbit:
            ZStack {
                Ellipse()
                    .stroke(accent.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .frame(width: 104, height: 58)
                ForEach(0..<6, id: \.self) { i in
                    let angle = Double(i) / 6 * 2 * .pi + .pi / 2
                    card(false, 14, 9).offset(x: 52 * cos(angle), y: 29 * sin(angle))
                }
                card(true, 38, 24)
            }
        case .spotlight:
            VStack(spacing: 6) {
                card(true, 70, 40)
                HStack(spacing: 4) { ForEach(0..<5, id: \.self) { i in card(false, 11, 7).opacity(i == 2 ? 1 : 0.6) } }
            }
        case .timeMachine:
            ZStack(alignment: .bottom) {
                ForEach((0..<5).reversed(), id: \.self) { i in
                    card(i == 0, 64, 38)
                        .scaleEffect(pow(0.84, Double(i)), anchor: .bottom)
                        .offset(y: -Double(i) * 7)
                        .opacity(1 - Double(i) * 0.18)
                }
            }
            .offset(y: 8)
        }
    }
}

private func openPane(_ anchor: String) {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
        NSWorkspace.shared.open(url)
    }
}

/// Click, then press the new combo. It needs ⌃, ⌥ or ⌘ so there's something to hold while cycling.
private struct ShortcutRecorder: View {
    let accent: Color

    @State private var shortcut = Shortcut.current
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Button(action: { recording ? stop() : start() }) {
                HStack(spacing: 4) {
                    if recording {
                        Text("Press a shortcut…")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(shortcut.display, id: \.self) { KeyCap($0) }
                    }
                }
                .frame(minWidth: 140, minHeight: 28)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(recording ? accent.opacity(0.15) : Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(recording ? accent : Color.primary.opacity(0.12), lineWidth: recording ? 2 : 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(recording ? "Press esc to cancel" : "Click to record a new shortcut")

            if shortcut != .standard && !recording {
                Button {
                    shortcut = .standard
                    shortcut.save()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help("Reset to ⌥⇥")
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        HotKeys.shared.paused = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            var modifiers: CGEventFlags = []
            if flags.contains(.control) { modifiers.insert(.maskControl) }
            if flags.contains(.option) { modifiers.insert(.maskAlternate) }
            if flags.contains(.command) { modifiers.insert(.maskCommand) }

            if event.keyCode == 53 && modifiers.isEmpty {
                stop()
                return nil
            }
            guard !modifiers.isEmpty else {
                NSSound.beep()
                return nil
            }
            shortcut = Shortcut(keyCode: Int64(event.keyCode), modifiers: modifiers, keyLabel: Self.label(for: event))
            shortcut.save()
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        HotKeys.shared.paused = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private static func label(for event: NSEvent) -> String {
        switch event.keyCode {
        case 48: "⇥"
        case 49: "Space"
        case 36: "↩"
        case 51: "⌫"
        case 123: "←"
        case 124: "→"
        case 125: "↓"
        case 126: "↑"
        default: event.charactersIgnoringModifiers?.uppercased() ?? "?"
        }
    }
}

