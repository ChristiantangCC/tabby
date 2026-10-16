// Renders Resources/AppIcon.icns. Run: swift scripts/make-icon.swift
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    let inset: CGFloat = 100
    let body = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 30
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor.black.setFill()
    squircle.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    NSGradient(colors: [
        NSColor(srgbRed: 0.36, green: 0.36, blue: 0.95, alpha: 1),
        NSColor(srgbRed: 0.04, green: 0.52, blue: 1.0, alpha: 1),
        NSColor(srgbRed: 0.39, green: 0.85, blue: 0.95, alpha: 1),
    ])!.draw(in: squircle, angle: -60)

    // Three window cards fanned back into depth.
    let cards: [(dx: CGFloat, dy: CGFloat, scale: CGFloat, alpha: CGFloat)] = [
        (-70, 110, 0.78, 0.35), (-35, 55, 0.89, 0.6), (0, 0, 1.0, 1.0),
    ]
    for card in cards {
        let w = 520 * card.scale, h = 360 * card.scale
        let rect = NSRect(x: size / 2 - w / 2 + 40 + card.dx, y: size / 2 - h / 2 - 50 + card.dy, width: w, height: h)
        let path = NSBezierPath(roundedRect: rect, xRadius: 42 * card.scale, yRadius: 42 * card.scale)
        NSGraphicsContext.current?.saveGraphicsState()
        let s = NSShadow()
        s.shadowColor = NSColor.black.withAlphaComponent(0.25 * card.alpha)
        s.shadowBlurRadius = 24
        s.shadowOffset = NSSize(width: 0, height: -10)
        s.set()
        NSColor.white.withAlphaComponent(card.alpha).setFill()
        path.fill()
        NSGraphicsContext.current?.restoreGraphicsState()
        if card.alpha == 1 {
            let bar = NSRect(x: rect.minX, y: rect.maxY - 64, width: rect.width, height: 64)
            NSGraphicsContext.current?.saveGraphicsState()
            path.addClip()
            NSColor(srgbRed: 0.04, green: 0.52, blue: 1.0, alpha: 0.18).setFill()
            bar.fill()
            NSGraphicsContext.current?.restoreGraphicsState()
            for (i, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
                color.setFill()
                NSBezierPath(ovalIn: NSRect(x: rect.minX + 32 + CGFloat(i) * 40, y: rect.maxY - 44, width: 24, height: 24)).fill()
            }
        }
    }
    return true
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
