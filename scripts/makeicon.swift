// Generates Assets/ReadMe.icns: an orange rounded squircle with a white
// speech bubble holding waveform bars. Run via make icon.
// StatusGlyph.swift draws the matching monochrome menu bar glyph.
import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let iconset = root.appendingPathComponent("Assets/ReadMe.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

let orange = NSColor(calibratedRed: 0.976, green: 0.451, blue: 0.086, alpha: 1) // #F97316

func draw(canvas: Int) -> NSImage {
    let s = CGFloat(canvas)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()
    defer { image.unlockFocus() }

    // Apple icon grid: artwork box is 824/1024 of the canvas, centered.
    let box = s * 824.0 / 1024.0
    let inset = (s - box) / 2
    let rect = NSRect(x: inset, y: inset, width: box, height: box)
    let radius = box * 0.225
    orange.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()

    // White speech bubble with a tail at bottom-left.
    let g = NSRect(x: inset + box * 0.2, y: inset + box * 0.2, width: box * 0.6, height: box * 0.6)
    let bubbleH = g.height * 0.82
    let bubble = NSRect(x: g.minX, y: g.maxY - bubbleH, width: g.width, height: bubbleH)
    let path = NSBezierPath(roundedRect: bubble, xRadius: bubbleH * 0.32, yRadius: bubbleH * 0.32)
    let tail = NSBezierPath()
    tail.move(to: NSPoint(x: g.minX + g.width * 0.18, y: bubble.minY + bubbleH * 0.1))
    tail.line(to: NSPoint(x: g.minX + g.width * 0.22, y: g.minY))
    tail.line(to: NSPoint(x: g.minX + g.width * 0.45, y: bubble.minY + bubbleH * 0.05))
    tail.close()
    path.append(tail)
    NSColor.white.setFill()
    path.fill()

    // Waveform bars inside the bubble, in the background orange.
    orange.setFill()
    let heights: [CGFloat] = [0.35, 0.7, 1.0, 0.7, 0.35]
    let barW = g.width * 0.08
    let gap = g.width * 0.05
    let total = CGFloat(heights.count) * barW + CGFloat(heights.count - 1) * gap
    var x = bubble.midX - total / 2
    let maxBar = bubbleH * 0.5
    for f in heights {
        let h = max(maxBar * f, barW)
        let bar = NSRect(x: x, y: bubble.midY - h / 2, width: barW, height: h)
        NSBezierPath(roundedRect: bar, xRadius: barW / 2, yRadius: barW / 2).fill()
        x += barW + gap
    }
    return image
}

func writePNG(_ image: NSImage, to url: URL, pixels: Int) throws {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

for size in sizes {
    let image = draw(canvas: size)
    if size <= 512 {
        try writePNG(image, to: iconset.appendingPathComponent("icon_\(size)x\(size).png"), pixels: size)
    }
    if size >= 32 {
        let half = size / 2
        try writePNG(
            draw(canvas: size),
            to: iconset.appendingPathComponent("icon_\(half)x\(half)@2x.png"),
            pixels: size
        )
    }
}
print("iconset written to \(iconset.path)")
