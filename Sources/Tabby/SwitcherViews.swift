import SwiftUI

/// Full-screen overlay: backdrop + whichever layout is chosen.
struct SwitcherRoot: View {
    @ObservedObject var model: SwitcherModel
    let onPick: (Int) -> Void
    let onDismiss: () -> Void

    @AppStorage(Prefs.layout) private var layout = LayoutStyle.grid
    @AppStorage(Prefs.surface) private var surface = SurfaceStyle.glass
    @AppStorage(Prefs.accent) private var accentHex = "#0A84FF"
    @AppStorage(Prefs.size) private var size = 1.0
    @AppStorage(Prefs.dim) private var dim = true
    @AppStorage(Prefs.titles) private var showTitles = true
    @AppStorage(Prefs.speed) private var speed = SwitchSpeed.fast

    private var theme: Theme {
        Theme(accent: Color(hex: accentHex), size: size, surface: surface, showTitles: showTitles, speed: speed)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Backdrop(layout: layout, dim: dim, accent: theme.accent)
                    .opacity(model.appeared ? 1 : 0)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)

                layoutView(bounds: geo.size)
                    .scaleEffect(model.appeared ? 1 : 0.94)
                    .opacity(model.appeared ? 1 : 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func layoutView(bounds: CGSize) -> some View {
        switch layout {
        case .grid: GridLayout(model: model, theme: theme, bounds: bounds, onPick: onPick)
        case .coverFlow: CoverFlowLayout(model: model, theme: theme, bounds: bounds, onPick: onPick)
        case .deck: DeckLayout(model: model, theme: theme, bounds: bounds, onPick: onPick)
        case .orbit: OrbitLayout(model: model, theme: theme, bounds: bounds, onPick: onPick)
        case .spotlight: SpotlightLayout(model: model, theme: theme, bounds: bounds, onPick: onPick)
        case .timeMachine: TimeMachineLayout(model: model, theme: theme, bounds: bounds, onPick: onPick)
        }
    }
}

// MARK: - Backdrop

struct Backdrop: View {
    let layout: LayoutStyle
    let dim: Bool
    let accent: Color

    var body: some View {
        ZStack {
            if dim {
                Color.black.opacity(layout == .timeMachine ? 0.55 : 0.32)
                RadialGradient(
                    colors: [accent.opacity(0.16), .clear],
                    center: .center, startRadius: 0, endRadius: 700
                )
            } else {
                Color.black.opacity(0.001)
            }
            if layout == .timeMachine {
                StarField()
            }
        }
    }
}

/// Deterministic star field for the Time Machine layout.
struct StarField: View {
    var body: some View {
        Canvas { context, size in
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func next() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double(seed >> 33) / Double(1 << 31)
            }
            for _ in 0..<260 {
                let point = CGPoint(x: next() * size.width, y: next() * size.height)
                let radius = 0.4 + next() * 1.4
                let alpha = 0.15 + next() * 0.65
                let rect = CGRect(x: point.x, y: point.y, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(alpha)))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Building blocks

/// Window picture (or app icon while the picture loads / for minimized windows).
struct Thumb: View {
    let item: WindowItem
    let image: NSImage?
    let size: CGSize
    var corner: CGFloat = 10
    var alignment: Alignment = .center
    var shadow = true
    /// Selection colour; the ring hugs the picture itself, not the layout box.
    var highlight: Color? = nil

    var body: some View {
        ZStack(alignment: alignment) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(highlight ?? .white.opacity(0.14), lineWidth: highlight == nil ? 1 : 3)
                    )
                    .shadow(color: highlight?.opacity(0.6) ?? .black.opacity(shadow ? 0.35 : 0), radius: highlight == nil ? 12 : 18, y: highlight == nil ? 6 : 0)
            } else {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(.primary.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(highlight ?? .primary.opacity(0.08), lineWidth: highlight == nil ? 1 : 3)
                    )
                    .shadow(color: highlight?.opacity(0.6) ?? .clear, radius: 18)
                    .overlay {
                        VStack(spacing: 6) {
                            Image(nsImage: item.icon)
                                .resizable()
                                .frame(width: min(size.width, size.height) * 0.4, height: min(size.width, size.height) * 0.4)
                            if item.isMinimized {
                                Text("Minimized")
                                    .font(.system(size: max(9, min(size.width, size.height) * 0.08), weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
            }
        }
        .frame(width: size.width, height: size.height, alignment: alignment)
    }
}

/// Selection glow shared by several layouts.
struct SelectionRing: ViewModifier {
    let active: Bool
    let accent: Color
    let corner: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(accent, lineWidth: active ? 3 : 0)
            )
            .shadow(color: accent.opacity(active ? 0.55 : 0), radius: 18)
    }
}

/// Icon + title + app name pill under hero-style layouts.
struct Caption: View {
    let item: WindowItem?
    let theme: Theme

    var body: some View {
        let s = theme.size
        HStack(spacing: 10 * s) {
            if let item {
                Image(nsImage: item.icon)
                    .resizable()
                    .frame(width: 28 * s, height: 28 * s)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.displayTitle)
                        .font(.system(size: 15 * s, weight: .semibold))
                        .lineLimit(1)
                    if !item.title.isEmpty {
                        Text(item.appName)
                            .font(.system(size: 12 * s))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: 520 * s)
        .padding(.horizontal, 16 * s)
        .padding(.vertical, 9 * s)
        .background(Capsule().fill(.primary.opacity(0.07)))
        .overlay(Capsule().strokeBorder(.primary.opacity(0.08), lineWidth: 1))
        .animation(nil, value: item?.id)
    }
}

/// The container chrome: glass, solid card, or nothing.
struct SurfaceBackground: ViewModifier {
    let theme: Theme
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let radius = 28 * min(theme.size, 1.3)
        switch theme.surface {
        case .glass:
            content
                .padding(22 * theme.size)
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(.black.opacity(0.3))
                            .blur(radius: 30)
                            .offset(y: 18)
                        VisualEffectBlur(material: scheme == .dark ? .hudWindow : .popover, cornerRadius: radius)
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.35), .white.opacity(0.06)],
                                    startPoint: .top, endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    }
                }
        case .solid:
            content
                .padding(22 * theme.size)
                .background {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .strokeBorder(.primary.opacity(0.1), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.35), radius: 40, y: 20)
                }
        case .frameless:
            content
        }
    }
}

/// Real behind-window blur (SwiftUI materials don't blur other apps' windows).
struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        update(view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        update(view)
    }

    private func update(_ view: NSVisualEffectView) {
        view.material = material
        view.maskImage = Self.mask(radius: cornerRadius)
    }

    private static func mask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
