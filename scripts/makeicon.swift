// Generates Assets/ReadMe.icns: a rounded squircle with an indigo to violet
// gradient and a white waveform glyph. Run via make icon.
import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let iconset = root.appendingPathComponent("Assets/ReadMe.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

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
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    let gradient = NSGradient(
        starting: NSColor(calibratedRed: 0.32, green: 0.18, blue: 0.85, alpha: 1),
        ending: NSColor(calibratedRed: 0.61, green: 0.32, blue: 0.95, alpha: 1)
    )!
    gradient.draw(in: path, angle: 90)

    // Soft top light: a gentle white fade over the whole squircle.
    let sheen = NSGradient(
        starting: NSColor.white.withAlphaComponent(0),
        ending: NSColor.white.withAlphaComponent(0.16)
    )!
    sheen.draw(in: path, angle: 90)

    // Waveform bars, the reading voice.
    let barCount = 7
    let heights: [CGFloat] = [0.22, 0.38, 0.58, 0.74, 0.58, 0.38, 0.22]
    let barWidth = box * 0.055
    let gap = box * 0.045
    let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * gap
    var x = inset + (box - totalWidth) / 2
    NSColor.white.setFill()
    for i in 0 ..< barCount {
        let h = box * heights[i]
        let bar = NSRect(x: x, y: inset + (box - h) / 2, width: barWidth, height: h)
        NSBezierPath(roundedRect: bar, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        x += barWidth + gap
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
