// Original vector artwork for Koala PSP. Rasterized with AppKit, no web assets.
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}
func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: radius, yRadius: radius)
}
func fill(_ shape: NSBezierPath, _ value: NSColor) { value.setFill(); shape.fill() }
func circle(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat, _ value: NSColor) {
    fill(NSBezierPath(ovalIn: NSRect(x: x-radius, y: y-radius, width: radius*2, height: radius*2)), value)
}
func gradient(_ shape: NSBezierPath, _ top: NSColor, _ bottom: NSColor) {
    NSGradient(starting: bottom, ending: top)!.draw(in: shape, angle: 90)
}
func artwork() {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = color(0.28, 0.09, 0.01, 0.28)
    shadow.shadowOffset = NSSize(width: 0, height: -12); shadow.shadowBlurRadius = 22; shadow.set()
    gradient(rounded(72, 72, 880, 880, 194), color(1, 0.67, 0.37), color(0.87, 0.30, 0.10))
    NSGraphicsContext.restoreGraphicsState()
    let tile = rounded(74, 74, 876, 876, 192)
    color(1, 1, 1, 0.25).setStroke(); tile.lineWidth = 3; tile.stroke()
    for x: CGFloat in [314, 710] {
        circle(x, 673, 121, color(0.25, 0.28, 0.31, 0.2))
        let ear = NSBezierPath(ovalIn: NSRect(x: x-119, y: 568, width: 238, height: 238))
        gradient(ear, color(0.95, 0.95, 0.93), color(0.63, 0.68, 0.68))
        circle(x, 687, 73, color(0.47, 0.53, 0.53))
        circle(x, 700, 59, color(0.65, 0.71, 0.70))
    }
    NSGraphicsContext.saveGraphicsState()
    let deviceShadow = NSShadow(); deviceShadow.shadowColor = color(0.25, 0.09, 0.03, 0.32)
    deviceShadow.shadowOffset = NSSize(width: 0, height: -20); deviceShadow.shadowBlurRadius = 22; deviceShadow.set()
    fill(rounded(158, 266, 708, 404, 170), color(0.36, 0.41, 0.41))
    NSGraphicsContext.restoreGraphicsState()
    gradient(rounded(158, 285, 708, 407, 166), color(0.96, 0.97, 0.94), color(0.74, 0.79, 0.77))
    gradient(rounded(343, 334, 338, 355, 148), color(0.83, 0.87, 0.84), color(0.66, 0.72, 0.70))
    circle(446, 535, 17, color(0.12, 0.17, 0.17)); circle(578, 535, 17, color(0.12, 0.17, 0.17))
    circle(450, 542, 4, color(1, 1, 1, 0.9)); circle(582, 542, 4, color(1, 1, 1, 0.9))
    gradient(rounded(468, 415, 88, 132, 43), color(0.20, 0.25, 0.25), color(0.08, 0.12, 0.13))
    fill(rounded(481, 486, 10, 38, 5), color(1, 1, 1, 0.13))
    let smile = NSBezierPath(); smile.move(to: NSPoint(x: 486, y: 393))
    smile.curve(to: NSPoint(x: 538, y: 393), controlPoint1: NSPoint(x: 500, y: 380), controlPoint2: NSPoint(x: 524, y: 380))
    color(0.23, 0.31, 0.29).setStroke(); smile.lineWidth = 7; smile.lineCapStyle = .round; smile.stroke()
    let ink = color(0.18, 0.24, 0.24)
    fill(rounded(222, 452, 116, 38, 9), ink); fill(rounded(261, 413, 38, 116, 9), ink)
    for (x,y): (CGFloat,CGFloat) in [(744,526),(797,473),(744,420),(691,473)] {
        circle(x, y-3, 20, color(0.63, 0.28, 0.11))
        circle(x, y, 19, color(0.93, 0.45, 0.20))
        circle(x-4, y+5, 5, color(1, 0.80, 0.53, 0.6))
    }
    fill(rounded(420, 310, 48, 9, 4.5), color(0.39, 0.47, 0.44))
    fill(rounded(556, 310, 48, 9, 4.5), color(0.39, 0.47, 0.44))
}
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current!.cgContext.scaleBy(x: CGFloat(size)/1024, y: CGFloat(size)/1024)
    artwork()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("icon-\(size).png"))
}
