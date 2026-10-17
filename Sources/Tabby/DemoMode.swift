import SwiftUI

/// `Tabby --demo -layout coverFlow` shows the switcher filled with made-up apps over a
/// generated wallpaper, for README screenshots that contain nobody's real windows.
enum DemoMode {
    static var isOn: Bool { CommandLine.arguments.contains("--demo") }

    /// The area the demo draws into (and that gets screenshotted).
    static let canvas = CGSize(width: 1400, height: 880)

    enum Kind { case code, photos, music, mail, notes, weather, chat, calendar }

    struct FakeApp {
        let name: String
        let title: String
        let symbol: String
        let colors: [Color]
        let kind: Kind
        let aspect: CGFloat
    }

    static let apps: [FakeApp] = [
        FakeApp(name: "Codepad", title: "main.swift — tabby", symbol: "chevron.left.forwardslash.chevron.right",
                colors: [Color(hex: "#5E5CE6"), Color(hex: "#2C2A8C")], kind: .code, aspect: 1.6),
        FakeApp(name: "Snaps", title: "Summer 2026", symbol: "photo.on.rectangle.angled",
                colors: [Color(hex: "#FF9F0A"), Color(hex: "#FF375F")], kind: .photos, aspect: 1.5),
        FakeApp(name: "Tunes", title: "Late Night Drive", symbol: "music.note",
                colors: [Color(hex: "#FF375F"), Color(hex: "#BF5AF2")], kind: .music, aspect: 1.45),
        FakeApp(name: "Inbox", title: "Inbox — 3 unread", symbol: "envelope.fill",
                colors: [Color(hex: "#64D2FF"), Color(hex: "#0A84FF")], kind: .mail, aspect: 1.6),
        FakeApp(name: "Jot", title: "Ideas", symbol: "note.text",
                colors: [Color(hex: "#FFD60A"), Color(hex: "#FF9F0A")], kind: .notes, aspect: 0.78),
        FakeApp(name: "Skies", title: "Copenhagen", symbol: "cloud.sun.fill",
                colors: [Color(hex: "#64D2FF"), Color(hex: "#5E5CE6")], kind: .weather, aspect: 1.25),
        FakeApp(name: "Chatter", title: "#design", symbol: "bubble.left.and.bubble.right.fill",
                colors: [Color(hex: "#30D158"), Color(hex: "#0A9F6E")], kind: .chat, aspect: 1.5),
        FakeApp(name: "Planner", title: "October 2026", symbol: "calendar",
                colors: [Color(hex: "#FF453A"), Color(hex: "#FF9F0A")], kind: .calendar, aspect: 1.55),
    ]

    /// Where some of the fake windows sit on the fake desktop (inside `canvas`).
    static let desktopFrames: [Int: CGRect] = [
        0: CGRect(x: 70, y: 60, width: 640, height: 400),
        1: CGRect(x: 760, y: 90, width: 560, height: 373),
        3: CGRect(x: 150, y: 470, width: 560, height: 350),
        5: CGRect(x: 880, y: 500, width: 400, height: 320),
    ]

    @MainActor
    static func items(canvasOrigin: CGPoint) -> [WindowItem] {
        apps.enumerated().map { index, app in
            WindowItem(
                id: CGWindowID(index + 1),
                pid: 0,
                appName: app.name,
                title: app.title,
                icon: render(FakeIcon(app: app), size: CGSize(width: 128, height: 128)),
                element: nil,
                localWindow: nil,
                isMinimized: false,
                aspect: app.aspect,
                frame: desktopFrames[index]?.offsetBy(dx: canvasOrigin.x, dy: canvasOrigin.y)
            )
        }
    }

    @MainActor
    static func thumbnails() -> [CGWindowID: NSImage] {
        var images: [CGWindowID: NSImage] = [:]
        for (index, app) in apps.enumerated() {
            let width: CGFloat = app.aspect < 1 ? 560 : 1100
            let frame = CGSize(width: width, height: width / app.aspect)
            images[CGWindowID(index + 1)] = render(FakeWindow(app: app, size: frame), size: frame)
        }
        return images
    }

    @MainActor
    private static func render<V: View>(_ view: V, size: CGSize) -> NSImage {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 2
        return renderer.nsImage ?? NSImage(size: size)
    }
}

// MARK: - Fake app art

private struct FakeIcon: View {
    let app: DemoMode.FakeApp

    var body: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(LinearGradient(colors: app.colors, startPoint: .top, endPoint: .bottom))
            .overlay(
                Image(systemName: app.symbol)
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .padding(6)
    }
}

/// Deterministic pseudo-random numbers so every screenshot run looks the same.
private struct Seeded {
    var state: UInt64
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 33) / Double(1 << 31)
    }
}

private struct FakeWindow: View {
    let app: DemoMode.FakeApp
    let size: CGSize

    private let ink = Color(white: 0.11)
    private let panel = Color(white: 0.15)
    private let line = Color(white: 0.26)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach([Color(hex: "#FF5F57"), Color(hex: "#FEBC2E"), Color(hex: "#28C840")], id: \.self) {
                    Circle().fill($0).frame(width: 13, height: 13)
                }
                Spacer()
                Text(app.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(white: 0.75))
                Spacer()
                Color.clear.frame(width: 55, height: 1)
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(panel)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ink)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var content: some View {
        switch app.kind {
        case .code: code
        case .photos: photos
        case .music: music
        case .mail: mail
        case .notes: notes
        case .weather: weather
        case .chat: chat
        case .calendar: calendar
        }
    }

    private func bar(_ width: CGFloat, _ color: Color, height: CGFloat = 10) -> some View {
        Capsule().fill(color).frame(width: width, height: height)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(0..<9, id: \.self) { i in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3).fill(i == 2 ? app.colors[0] : line).frame(width: 14, height: 14)
                    bar(CGFloat(60 + (i * 37) % 70), i == 2 ? Color(white: 0.8) : line)
                }
            }
            Spacer()
        }
        .padding(18)
        .frame(width: 210)
        .frame(maxHeight: .infinity)
        .background(panel.opacity(0.6))
    }

    private var code: some View {
        var rng = Seeded(state: 7)
        let palette = [Color(hex: "#FF7AB2"), Color(hex: "#6BDFFF"), Color(hex: "#D9C97C"), Color(hex: "#B281EB"), Color(white: 0.7)]
        let lines: [(indent: Int, parts: [(CGFloat, Color)])] = (0..<26).map { _ in
            let indent = Int(rng.next() * 4)
            let count = 1 + Int(rng.next() * 4)
            return (indent, (0..<count).map { _ in (CGFloat(30 + rng.next() * 120), palette[Int(rng.next() * 5)]) })
        }
        return HStack(spacing: 0) {
            sidebar
            VStack(alignment: .leading, spacing: 11) {
                ForEach(lines.indices, id: \.self) { i in
                    HStack(spacing: 8) {
                        Text("\(i + 1)").font(.system(size: 11, design: .monospaced)).foregroundStyle(Color(white: 0.35)).frame(width: 22, alignment: .trailing)
                        Color.clear.frame(width: CGFloat(lines[i].indent) * 26, height: 1)
                        ForEach(lines[i].parts.indices, id: \.self) { p in
                            bar(lines[i].parts[p].0, lines[i].parts[p].1.opacity(0.85), height: 9)
                        }
                    }
                }
                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var photos: some View {
        var rng = Seeded(state: 11)
        let hues = (0..<15).map { _ in rng.next() }
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
            ForEach(hues.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(
                        colors: [Color(hue: hues[i], saturation: 0.6, brightness: 0.95), Color(hue: (hues[i] + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.8, brightness: 0.6)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .aspectRatio(1.2, contentMode: .fit)
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var music: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 14) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(colors: app.colors + [Color(hex: "#FF9F0A")], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 300, height: 300)
                    .overlay(Image(systemName: "waveform").font(.system(size: 110, weight: .bold)).foregroundStyle(.white.opacity(0.85)))
                Text("Late Night Drive").font(.system(size: 26, weight: .bold)).foregroundStyle(.white)
                Text("Neon Harbour").font(.system(size: 17)).foregroundStyle(Color(white: 0.6))
            }
            VStack(spacing: 18) {
                ForEach(0..<10, id: \.self) { i in
                    HStack(spacing: 14) {
                        Text("\(i + 1)").font(.system(size: 14, design: .rounded)).foregroundStyle(Color(white: 0.45)).frame(width: 20)
                        bar(CGFloat(140 + (i * 53) % 160), i == 2 ? app.colors[0] : Color(white: 0.55))
                        Spacer()
                        bar(36, Color(white: 0.35))
                    }
                }
            }
            .padding(.top, 8)
        }
        .padding(30)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var mail: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { i in
                    HStack(alignment: .top, spacing: 12) {
                        Circle().fill(i < 3 ? app.colors[1] : .clear).frame(width: 9, height: 9).padding(.top, 5)
                        VStack(alignment: .leading, spacing: 8) {
                            bar(CGFloat(110 + (i * 29) % 80), Color(white: 0.8))
                            bar(CGFloat(180 + (i * 41) % 60), Color(white: 0.4), height: 8)
                            bar(CGFloat(150 + (i * 17) % 90), Color(white: 0.3), height: 8)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(i == 0 ? app.colors[1].opacity(0.35) : .clear)
                }
                Spacer()
            }
            .frame(width: 330)
            .background(panel.opacity(0.6))
            VStack(alignment: .leading, spacing: 14) {
                bar(260, .white, height: 16)
                bar(160, Color(white: 0.45))
                Color.clear.frame(height: 10)
                ForEach(0..<9, id: \.self) { i in bar(CGFloat(380 + (i * 67) % 220), Color(white: 0.33), height: 9) }
                Spacer()
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ideas").font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
            ForEach(0..<14, id: \.self) { i in
                HStack(spacing: 10) {
                    Circle().fill(i % 4 == 0 ? app.colors[0] : Color(white: 0.4)).frame(width: 9, height: 9)
                    bar(CGFloat(180 + (i * 59) % 200), Color(white: i % 4 == 0 ? 0.8 : 0.4), height: 9)
                }
            }
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "#1E1B12"))
    }

    private var weather: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "#3A7BD5"), Color(hex: "#6A5ACD")], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 10) {
                Text("Copenhagen").font(.system(size: 26, weight: .medium)).foregroundStyle(.white)
                Text("14°").font(.system(size: 110, weight: .thin)).foregroundStyle(.white)
                Text("Partly cloudy").font(.system(size: 20)).foregroundStyle(.white.opacity(0.8))
                HStack(spacing: 22) {
                    ForEach(0..<6, id: \.self) { i in
                        VStack(spacing: 10) {
                            Text("\(12 + i)").font(.system(size: 15, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                            Image(systemName: i % 3 == 0 ? "sun.max.fill" : "cloud.sun.fill")
                                .symbolRenderingMode(.multicolor)
                                .font(.system(size: 26))
                            Text("\(14 - i / 2)°").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        }
                    }
                }
                .padding(20)
                .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.15)))
                .padding(.top, 18)
            }
        }
    }

    private var chat: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 16) {
                ForEach(0..<7, id: \.self) { i in
                    let mine = i % 3 == 1
                    HStack(alignment: .bottom, spacing: 10) {
                        if mine { Spacer() } else {
                            Circle().fill(LinearGradient(colors: [Color(hue: Double(i) / 7, saturation: 0.6, brightness: 0.9), .gray], startPoint: .top, endPoint: .bottom)).frame(width: 34, height: 34)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            bar(CGFloat(160 + (i * 47) % 160), mine ? .white.opacity(0.9) : Color(white: 0.7), height: 9)
                            if i % 2 == 0 { bar(CGFloat(100 + (i * 31) % 90), mine ? .white.opacity(0.7) : Color(white: 0.5), height: 9) }
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 16).fill(mine ? app.colors[1] : panel))
                        if !mine { Spacer() }
                    }
                }
                Spacer()
            }
            .padding(22)
        }
    }

    private var calendar: some View {
        VStack(spacing: 6) {
            HStack {
                ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) {
                    Text($0).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(white: 0.55)).frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<5, id: \.self) { week in
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { day in
                        let n = week * 7 + day
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(n + 1)").font(.system(size: 13, weight: n == 16 ? .bold : .regular))
                                .foregroundStyle(n == 16 ? app.colors[0] : Color(white: 0.7))
                            if n % 5 == 1 { RoundedRectangle(cornerRadius: 4).fill(app.colors[0].opacity(0.8)).frame(height: 14) }
                            if n % 7 == 3 { RoundedRectangle(cornerRadius: 4).fill(Color(hex: "#0A84FF").opacity(0.8)).frame(height: 14) }
                            Spacer()
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(panel))
                    }
                }
            }
        }
        .padding(18)
    }
}

// MARK: - Wallpaper behind the demo

struct DemoWallpaper: View {
    /// Fake windows drawn on the desktop at `DemoMode.desktopFrames`.
    var windows: [CGWindowID: NSImage] = [:]

    var body: some View {
        ZStack(alignment: .topLeading) {
            wallpaper
            ForEach(DemoMode.desktopFrames.sorted { $0.key > $1.key }, id: \.key) { index, frame in
                if let image = windows[CGWindowID(index + 1)] {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: frame.width, height: frame.height)
                        .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
                        .offset(x: frame.minX, y: frame.minY)
                }
            }
        }
        .frame(width: DemoMode.canvas.width, height: DemoMode.canvas.height, alignment: .topLeading)
        .clipped()
    }

    private var wallpaper: some View {
        ZStack {
            Color(hex: "#0D1030")
            Circle().fill(Color(hex: "#5E5CE6")).frame(width: 900).offset(x: -500, y: -300).blur(radius: 160)
            Circle().fill(Color(hex: "#FF375F")).frame(width: 700).offset(x: 560, y: -260).blur(radius: 170)
            Circle().fill(Color(hex: "#FF9F0A")).frame(width: 600).offset(x: 420, y: 420).blur(radius: 170)
            Circle().fill(Color(hex: "#30D158")).frame(width: 520).offset(x: -460, y: 440).blur(radius: 180).opacity(0.7)
        }
        .frame(width: DemoMode.canvas.width, height: DemoMode.canvas.height)
    }
}
