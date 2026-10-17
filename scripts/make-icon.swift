// Renders Resources/AppIcon.icns: a macOS window that is also a tabby cat.
// Run: swift scripts/make-icon.swift && iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
import AppKit

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha
    )
}

func withShadow(_ shadowColor: NSColor, blur: CGFloat, dy: CGFloat, _ draw: () -> Void) {
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = shadowColor
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = NSSize(width: 0, height: dy)
    shadow.set()
    draw()
    NSGraphicsContext.current?.restoreGraphicsState()
}

func triangle(_ points: [NSPoint], lineWidth: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: points[0])
    path.line(to: points[1])
    path.line(to: points[2])
    path.close()
    path.lineWidth = lineWidth
    path.lineJoinStyle = .round
    return path
}

/// Shrinks a triangle toward its centre, so the inner ear always sits inside the outer one.
func shrink(_ points: [NSPoint], by factor: CGFloat, lift: CGFloat) -> [NSPoint] {
    let cx = points.map(\.x).reduce(0, +) / 3
    let cy = points.map(\.y).reduce(0, +) / 3
    return points.map { NSPoint(x: cx + ($0.x - cx) * factor, y: cy + ($0.y - cy) * factor + lift) }
}

func stripe(from: NSPoint, to: NSPoint, width: CGFloat, _ stroke: NSColor) {
    let path = NSBezierPath()
    path.move(to: from)
    path.line(to: to)
    path.lineWidth = width
    path.lineCapStyle = .round
    stroke.setStroke()
    path.stroke()
}

func drawIcon() {
    // Background squircle on Apple's 824pt icon grid.
    let plate = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    withShadow(color(0, 0.35), blur: 30, dy: -12) { color(0).setFill(); plate.fill() }
    NSGradient(starting: color(0x6E7CFF), ending: color(0x3A2FB8))!.draw(in: plate, angle: -90)
    NSGraphicsContext.current?.saveGraphicsState()
    plate.addClip()
    NSGradient(starting: color(0xFFFFFF, 0.18), ending: color(0xFFFFFF, 0))!
        .draw(in: NSRect(x: 100, y: 560, width: 824, height: 364), angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()

    // The window, with ears.
    let frame = NSRect(x: 196, y: 214, width: 632, height: 500)
    let window = NSBezierPath(roundedRect: frame, xRadius: 64, yRadius: 64)
    let leftEar = [NSPoint(x: 236, y: 660), NSPoint(x: 274, y: 842), NSPoint(x: 414, y: 700)]
    let rightEar = leftEar.map { NSPoint(x: 1024 - $0.x, y: $0.y) }
    withShadow(color(0x140A60, 0.55), blur: 36, dy: -16) {
        color(0xFFFFFF).setFill()
        color(0xFFFFFF).setStroke()
        for ear in [leftEar, rightEar] {
            let path = triangle(ear, lineWidth: 48)
            path.fill()
            path.stroke()
        }
        window.fill()
    }

    // Title bar in warm tabby cream, with traffic lights.
    NSGraphicsContext.current?.saveGraphicsState()
    window.addClip()
    color(0xFFE2C6).setFill()
    NSRect(x: frame.minX, y: frame.maxY - 110, width: frame.width, height: 110).fill()
    NSGraphicsContext.current?.restoreGraphicsState()
    for (index, light) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
        color(UInt32(light)).setFill()
        NSBezierPath(ovalIn: NSRect(x: 252 + CGFloat(index) * 52, y: 637, width: 34, height: 34)).fill()
    }

    // Inner ears.
    color(0xFFB27A).setFill()
    color(0xFFB27A).setStroke()
    for ear in [leftEar, rightEar] {
        let path = triangle(shrink(ear, by: 0.52, lift: 14), lineWidth: 16)
        path.fill()
        path.stroke()
    }

    // Tabby stripes on the forehead.
    let orange = color(0xF07F22)
    stripe(from: NSPoint(x: 512, y: 690), to: NSPoint(x: 512, y: 640), width: 26, orange)
    stripe(from: NSPoint(x: 462, y: 686), to: NSPoint(x: 470, y: 646), width: 22, orange)
    stripe(from: NSPoint(x: 562, y: 686), to: NSPoint(x: 554, y: 646), width: 22, orange)

    // Eyes with a catch light.
    for x: CGFloat in [408, 616] {
        color(0x23201E).setFill()
        NSBezierPath(ovalIn: NSRect(x: x - 33, y: 470 - 43, width: 66, height: 86)).fill()
        color(0xFFFFFF).setFill()
        NSBezierPath(ovalIn: NSRect(x: x - 3, y: 477, width: 24, height: 24)).fill()
    }

    // Nose and mouth.
    let nose = triangle([NSPoint(x: 489, y: 393), NSPoint(x: 535, y: 393), NSPoint(x: 512, y: 367)], lineWidth: 9)
    color(0xF2879A).setFill()
    color(0xF2879A).setStroke()
    nose.fill()
    nose.stroke()
    let mouth = NSBezierPath()
    mouth.lineWidth = 8
    mouth.lineCapStyle = .round
    for side: CGFloat in [-1, 1] {
        mouth.move(to: NSPoint(x: 512, y: 367))
        mouth.curve(
            to: NSPoint(x: 512 + side * 43, y: 344),
            controlPoint1: NSPoint(x: 512, y: 344),
            controlPoint2: NSPoint(x: 512 + side * 27, y: 339)
        )
    }
    color(0x23201E).setStroke()
    mouth.stroke()
}

let iconset = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = base * scale
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        drawIcon()
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
