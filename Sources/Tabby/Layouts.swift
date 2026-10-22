import SwiftUI


private extension SwitcherModel {
    var enumerated: [(offset: Int, element: WindowItem)] { Array(items.enumerated()) }
}

// MARK: - Thumbnails (grid)

struct GridLayout: View {
    @ObservedObject var model: SwitcherModel
    let theme: Theme
    let bounds: CGSize
    let onPick: (Int) -> Void

    @Namespace private var ns

    var body: some View {
        let (fitted, rowWidth) = fit()
        let s = fitted.size

        FlowRows(spacing: 8 * s, maxWidth: rowWidth) {
            ForEach(model.enumerated, id: \.element.id) { index, item in
                GridTile(
                    item: item,
                    image: model.thumbs[item.id],
                    theme: fitted,
                    thumbSize: Self.thumbSize(item, fitted),
                    selected: index == model.selected,
                    ns: ns
                )
                .contentShape(Rectangle())
                .onTapGesture { onPick(index) }
            }
        }
        .modifier(SurfaceBackground(theme: fitted))
        .animation(theme.speed.spring(0.34, 0.82), value: model.selected)
    }

    /// Every tile shares one height; its width follows the window's own shape (like AltTab).
    static func thumbSize(_ item: WindowItem, _ theme: Theme) -> CGSize {
        let height = theme.thumb.height
        return CGSize(width: height * min(max(item.aspect, 0.6), 2.4), height: height)
    }

    /// Shrinks tiles until every row fits on screen; caps row width so wide screens get a block, not a ribbon.
    private func fit() -> (Theme, CGFloat) {
        let count = max(model.items.count, 1)
        var factor = 1.0
        while true {
            let t = theme.scaled(by: factor)
            let s = CGFloat(t.size)
            let spacing = 8 * s
            let widths = model.items.map { Self.thumbSize($0, t).width + 20 * s }
            let average = widths.isEmpty ? t.thumb.width : widths.reduce(0, +) / CGFloat(widths.count)
            let perRow = CGFloat(max(4, Int((Double(count) * 1.8).squareRoot().rounded(.up))))
            let rowWidth = min(bounds.width * 0.9 - 44 * s, (average + spacing) * perRow)
            let rows = FlowRows.rowCount(widths: widths, spacing: spacing, maxWidth: rowWidth)
            let tileHeight = t.thumb.height + 20 * s + (t.showTitles ? 28 * s : 0)
            if CGFloat(rows) * (tileHeight + spacing) + 44 * s <= bounds.height * 0.86 || factor < 0.35 {
                return (t, rowWidth)
            }
            factor *= 0.9
        }
    }
}

/// Wraps children into centred rows.
struct FlowRows: Layout {
    var spacing: CGFloat
    var maxWidth: CGFloat

    static func rowCount(widths: [CGFloat], spacing: CGFloat, maxWidth: CGFloat) -> Int {
        var rows = widths.isEmpty ? 0 : 1
        var x: CGFloat = 0
        for width in widths {
            if x > 0 && x + spacing + width > maxWidth {
                rows += 1
                x = width
            } else {
                x += (x > 0 ? spacing : 0) + width
            }
        }
        return rows
    }

    private func rows(_ sizes: [CGSize]) -> [[Int]] {
        var rows: [[Int]] = []
        var current: [Int] = []
        var x: CGFloat = 0
        for (index, size) in sizes.enumerated() {
            if !current.isEmpty && x + spacing + size.width > maxWidth {
                rows.append(current)
                current = []
                x = 0
            }
            x += (current.isEmpty ? 0 : spacing) + size.width
            current.append(index)
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }

    private func rowSize(_ row: [Int], _ sizes: [CGSize]) -> CGSize {
        let width = row.map { sizes[$0].width }.reduce(0, +) + spacing * CGFloat(max(row.count - 1, 0))
        let height = row.map { sizes[$0].height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let rowSizes = rows(sizes).map { rowSize($0, sizes) }
        let width = rowSizes.map(\.width).max() ?? 0
        let height = rowSizes.map(\.height).reduce(0, +) + spacing * CGFloat(max(rowSizes.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var y = bounds.minY
        for row in rows(sizes) {
            let size = rowSize(row, sizes)
            var x = bounds.minX + (bounds.width - size.width) / 2
            for index in row {
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
                x += sizes[index].width + spacing
            }
            y += size.height + spacing
        }
    }
}

private struct GridTile: View {
    let item: WindowItem
    let image: NSImage?
    let theme: Theme
    let thumbSize: CGSize
    let selected: Bool
    let ns: Namespace.ID

    var body: some View {
        let s = theme.size
        VStack(spacing: 8 * s) {
            ZStack(alignment: .bottomLeading) {
                Thumb(item: item, image: image, size: thumbSize, corner: 9 * s)
                    .modifier(CloseBadge(item: item, selected: selected, scale: s))
                Image(nsImage: item.icon)
                    .resizable()
                    .frame(width: 34 * s, height: 34 * s)
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                    .offset(x: -8 * s, y: 10 * s)
            }
            if theme.showTitles {
                Text(item.displayTitle)
                    .font(.system(size: 12 * s, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .primary : .secondary)
                    .lineLimit(1)
                    .frame(width: thumbSize.width)
            }
        }
        .padding(10 * s)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 16 * s, style: .continuous)
                    .fill(theme.accent.opacity(0.22))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16 * s, style: .continuous)
                            .strokeBorder(theme.accent, lineWidth: 2.5)
                    )
                    .shadow(color: theme.accent.opacity(0.5), radius: 16)
                    .matchedGeometryEffect(id: "selection", in: ns)
            }
        }
        .scaleEffect(selected ? 1.04 : 1)
        .zIndex(selected ? 1 : 0)
    }
}

// MARK: - Cover Flow

struct CoverFlowLayout: View {
    @ObservedObject var model: SwitcherModel
    let theme: Theme
    let bounds: CGSize
    let onPick: (Int) -> Void

    var body: some View {
        let s = theme.size
        let card = CGSize(width: min(380 * s, bounds.width * 0.36), height: min(240 * s, bounds.height * 0.32))
        let width = min(bounds.width * 0.92, card.width * 5.2)

        VStack(spacing: 14 * s) {
            ZStack {
                ForEach(model.enumerated, id: \.element.id) { index, item in
                    let d = Double(index - model.selected)
                    let side: Double = d < 0 ? -1 : 1
                    let x = d == 0 ? 0 : side * (card.width * 0.66 + (abs(d) - 1) * card.width * 0.24)

                    CoverCard(item: item, image: model.thumbs[item.id], size: card, theme: theme, selected: d == 0)
                        .rotation3DEffect(
                            .degrees(d == 0 ? 0 : side * 62),
                            axis: (x: 0, y: 1, z: 0),
                            perspective: 0.5
                        )
                        .scaleEffect(d == 0 ? 1.06 : 0.88)
                        .offset(x: x)
                        .zIndex(-abs(d))
                        .opacity(abs(d) > 8 ? 0 : 1)
                        .onTapGesture { onPick(index) }
                }
            }
            .frame(width: width, height: card.height * 1.5)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.12),
                        .init(color: .black, location: 0.88),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
            )

            Caption(item: model.current, theme: theme)
        }
        .modifier(SurfaceBackground(theme: theme))
        .animation(theme.speed.spring(0.45, 0.85), value: model.selected)
    }
}

private struct CoverCard: View {
    let item: WindowItem
    let image: NSImage?
    let size: CGSize
    let theme: Theme
    let selected: Bool

    var body: some View {
        VStack(spacing: 3) {
            Thumb(item: item, image: image, size: size, corner: 8, alignment: .bottom)
                .modifier(CloseBadge(item: item, selected: selected, scale: theme.size))
            // Mirror reflection on the "floor".
            Thumb(item: item, image: image, size: size, corner: 8, alignment: .bottom, shadow: false)
                .scaleEffect(x: 1, y: -1)
                .frame(height: size.height * 0.4, alignment: .top)
                .clipped()
                .mask(
                    LinearGradient(
                        colors: [.black.opacity(0.32), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                )
        }
        .frame(height: size.height * 1.4 + 3, alignment: .top)
        .offset(y: size.height * 0.2)
        .brightness(selected ? 0 : -0.08)
    }
}

// MARK: - Deck

struct DeckLayout: View {
    @ObservedObject var model: SwitcherModel
    let theme: Theme
    let bounds: CGSize
    let onPick: (Int) -> Void

    var body: some View {
        let s = theme.size
        let card = CGSize(width: 250 * s, height: 190 * s)
        let count = model.items.count
        // Wider fan: up to 13° between cards, ~100° across the whole hand.
        let spread = count > 1 ? min(13.0, 100.0 / Double(count - 1)) : 0
        let middle = Double(count - 1) / 2
        // Cards pivot around a point below the hand, like fingers holding them.
        let pivot: CGFloat = 3.6
        let radius = card.height * (pivot - 0.5)
        let maxAngle = spread * middle * .pi / 180
        let lift = card.height * 0.5
        let drop = radius * (1 - cos(maxAngle)) + card.width / 2 * sin(maxAngle) + card.height * 0.2
        let halfWidth = radius * sin(maxAngle) + card.width * 0.6

        VStack(spacing: 18 * s) {
            ZStack(alignment: .top) {
                ForEach(model.enumerated, id: \.element.id) { index, item in
                    let selected = index == model.selected
                    DeckCard(item: item, image: model.thumbs[item.id], size: card, theme: theme, selected: selected)
                        .scaleEffect(selected ? 1.14 : 1)
                        .offset(y: selected ? -card.height * 0.38 : 0)
                        .rotationEffect(
                            .degrees((Double(index) - middle) * spread),
                            anchor: UnitPoint(x: 0.5, y: pivot)
                        )
                        .zIndex(selected ? 1000 : Double(index))
                        .onTapGesture { onPick(index) }
                }
            }
            .padding(.top, lift)
            .frame(width: min(bounds.width * 0.9, halfWidth * 2), height: lift + card.height + drop, alignment: .top)

            Caption(item: model.current, theme: theme)
        }
        .modifier(SurfaceBackground(theme: theme))
        .animation(theme.speed.spring(0.38, 0.78), value: model.selected)
    }
}

private struct DeckCard: View {
    let item: WindowItem
    let image: NSImage?
    let size: CGSize
    let theme: Theme
    let selected: Bool

    var body: some View {
        let s = theme.size
        let corner = 16 * s
        VStack(spacing: 8 * s) {
            Thumb(item: item, image: image, size: CGSize(width: size.width - 20 * s, height: size.height - 58 * s), corner: 7 * s, shadow: false)
            HStack(spacing: 7 * s) {
                Image(nsImage: item.icon).resizable().frame(width: 22 * s, height: 22 * s)
                Text(item.appName)
                    .font(.system(size: 12 * s, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .padding(10 * s)
        .frame(width: size.width, height: size.height)
        .background(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(.primary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 10, y: 5)
        .modifier(SelectionRing(active: selected, accent: theme.accent, corner: corner))
        .modifier(CloseBadge(item: item, selected: selected, scale: s))
    }
}

// MARK: - Orbit

struct OrbitLayout: View {
    @ObservedObject var model: SwitcherModel
    let theme: Theme
    let bounds: CGSize
    let onPick: (Int) -> Void

    var body: some View {
        let s = theme.size
        let hero = CGSize(width: min(440 * s, bounds.width * 0.4), height: min(280 * s, bounds.height * 0.34))
        let satellite = CGSize(width: 150 * s, height: 96 * s)
        let rx = min(bounds.width * 0.4, hero.width * 1.35)
        let ry = min(bounds.height * 0.36, hero.height * 1.25)
        let count = max(model.items.count, 1)

        ZStack {
            Ellipse()
                .stroke(theme.accent.opacity(0.35), style: StrokeStyle(lineWidth: 1.2, dash: [3, 7]))
                .frame(width: rx * 2, height: ry * 2)

            ForEach(model.enumerated, id: \.element.id) { index, item in
                let angle = Double.pi / 2 + 2 * Double.pi * (Double(index) - model.spin) / Double(count)
                let selected = index == model.selected
                Thumb(item: item, image: model.thumbs[item.id], size: satellite, corner: 8 * s,
                      highlight: selected ? theme.accent : nil)
                    .modifier(CloseBadge(item: item, selected: selected, scale: s))
                    .modifier(OrbitEffect(angle: angle, rx: rx, ry: ry))
                    .opacity(0.45 + 0.55 * (sin(angle) + 1) / 2)
                    .zIndex(sin(angle))
                    .onTapGesture { onPick(index) }
            }

            if let current = model.current {
                VStack(spacing: 14 * s) {
                    Thumb(item: current, image: model.thumbs[current.id], size: hero, corner: 12 * s)
                    Caption(item: current, theme: theme)
                }
                .id(current.id)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.86).combined(with: .opacity),
                    removal: .opacity
                ))
                .zIndex(0.5)
            }
        }
        .frame(width: rx * 2 + satellite.width, height: ry * 2 + satellite.height + 30 * s)
        .modifier(SurfaceBackground(theme: theme))
        .animation(theme.speed.spring(0.5, 0.82), value: model.spin)
    }
}

/// Moves a view along an ellipse; animating `angle` makes it travel the arc, not a straight line.
private struct OrbitEffect: GeometryEffect {
    var angle: Double
    let rx: CGFloat
    let ry: CGFloat

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let depth = (sin(angle) + 1) / 2
        let scale = 0.62 + 0.45 * depth
        let x = rx * cos(angle) + size.width / 2 * (1 - scale)
        let y = ry * sin(angle) + size.height / 2 * (1 - scale)
        return ProjectionTransform(CGAffineTransform(translationX: x, y: y).scaledBy(x: scale, y: scale))
    }
}

// MARK: - Spotlight

struct SpotlightLayout: View {
    @ObservedObject var model: SwitcherModel
    let theme: Theme
    let bounds: CGSize
    let onPick: (Int) -> Void

    var body: some View {
        let s = theme.size
        let hero = CGSize(width: min(bounds.width * 0.6, 980 * s), height: min(bounds.height * 0.52, 600 * s))
        let chip = CGSize(width: 112 * s, height: 72 * s)
        let visible = visibleRange(chipWidth: chip.width + 12 * s, maxWidth: hero.width)

        VStack(spacing: 18 * s) {
            ZStack {
                if let current = model.current {
                    Thumb(item: current, image: model.thumbs[current.id], size: hero, corner: 14 * s)
                        .id(current.id)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.97).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
            }
            .frame(width: hero.width, height: hero.height)

            Caption(item: model.current, theme: theme)

            HStack(spacing: 12 * s) {
                ForEach(model.enumerated[visible], id: \.element.id) { index, item in
                    let selected = index == model.selected
                    Thumb(item: item, image: model.thumbs[item.id], size: chip, corner: 7 * s, shadow: false,
                          highlight: selected ? theme.accent : nil)
                        .modifier(CloseBadge(item: item, selected: selected, scale: s))
                        .scaleEffect(selected ? 1.2 : 1, anchor: .bottom)
                        .opacity(selected ? 1 : 0.6)
                        .onTapGesture { onPick(index) }
                }
            }
            .padding(.top, 12 * s)
        }
        .modifier(SurfaceBackground(theme: theme))
        .animation(theme.speed.spring(0.3, 0.86), value: model.selected)
    }

    /// Window of chips around the selection that fits under the hero.
    private func visibleRange(chipWidth: CGFloat, maxWidth: CGFloat) -> Range<Int> {
        let count = model.items.count
        let fits = max(1, Int(maxWidth / chipWidth))
        guard count > fits else { return 0..<count }
        let start = min(max(0, model.selected - fits / 2), count - fits)
        return start..<(start + fits)
    }
}

// MARK: - Time Machine

struct TimeMachineLayout: View {
    @ObservedObject var model: SwitcherModel
    let theme: Theme
    let bounds: CGSize
    let onPick: (Int) -> Void

    var body: some View {
        let s = theme.size
        let card = CGSize(width: min(640 * s, bounds.width * 0.55), height: min(400 * s, bounds.height * 0.45))

        VStack(spacing: 26 * s) {
            ZStack(alignment: .bottom) {
                ForEach(model.enumerated, id: \.element.id) { index, item in
                    let d = Double(index - model.selected)
                    Thumb(item: item, image: model.thumbs[item.id], size: card, corner: 12 * s, alignment: .bottom,
                          highlight: d == 0 ? theme.accent : nil)
                        .modifier(CloseBadge(item: item, selected: d == 0, scale: s))
                        .scaleEffect(d >= 0 ? pow(0.86, d) : 1.3, anchor: .bottom)
                        .offset(y: d >= 0 ? -d * card.height * 0.16 : card.height * 0.6)
                        .opacity(d < 0 ? 0 : max(0, 1 - d * 0.17))
                        .blur(radius: d > 0 ? min(d * 1.3, 6) : 0)
                        .zIndex(-d)
                        .allowsHitTesting(d >= 0 && d < 6)
                        .onTapGesture { onPick(index) }
                }
            }
            .frame(width: card.width, height: card.height * 1.75, alignment: .bottom)

            Caption(item: model.current, theme: theme)
        }
        .modifier(SurfaceBackground(theme: theme))
        .animation(theme.speed.spring(0.45, 0.86), value: model.selected)
    }
}
