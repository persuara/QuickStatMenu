// persuara

import AppKit

func drawIcon(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)

    let body = NSRect(x: s * 0.098, y: s * 0.098, width: s * 0.804, height: s * 0.804)
    let path = NSBezierPath(roundedRect: body, xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(colors: [NSColor(red: 0.20, green: 0.22, blue: 0.28, alpha: 1),
                        NSColor(red: 0.07, green: 0.08, blue: 0.11, alpha: 1)])!
        .draw(in: path, angle: -90)

    let colors = [NSColor(red: 0.20, green: 0.80, blue: 0.35, alpha: 1),
                  NSColor(red: 1.00, green: 0.80, blue: 0.10, alpha: 1),
                  NSColor(red: 1.00, green: 0.35, blue: 0.25, alpha: 1)]
    let heights: [CGFloat] = [0.38, 0.58, 0.78]
    let barW = body.width * 0.15, gap = body.width * 0.09
    let total = barW * 3 + gap * 2
    let x0 = body.midX - total / 2
    let maxH = body.height * 0.62, baseY = body.minY + body.height * 0.17
    for i in 0..<3 {
        let track = NSRect(x: x0 + CGFloat(i) * (barW + gap), y: baseY, width: barW, height: maxH)
        NSColor.white.withAlphaComponent(0.10).setFill()
        NSBezierPath(roundedRect: track, xRadius: barW / 2, yRadius: barW / 2).fill()
        var fill = track; fill.size.height = maxH * heights[i]
        colors[i].setFill()
        NSBezierPath(roundedRect: fill, xRadius: barW / 2, yRadius: barW / 2).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let set = "Resources/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: set)
try! FileManager.default.createDirectory(atPath: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! drawIcon(base).write(to: URL(fileURLWithPath: "\(set)/icon_\(base)x\(base).png"))
    try! drawIcon(base * 2).write(to: URL(fileURLWithPath: "\(set)/icon_\(base)x\(base)@2x.png"))
}
