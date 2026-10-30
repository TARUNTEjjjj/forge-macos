import AppKit
import Foundation

// A vector-built Forge mark. No external art or font is required.
let output = CommandLine.arguments.dropFirst().first ?? "Config/AppIcon-1024.png"
let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
}
let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 196, yRadius: 196)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowBlurRadius = 22
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.set()
color(11, 16, 32).setFill()
tile.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(starting: color(33, 45, 71), ending: color(11, 16, 32))!.draw(in: tile, angle: -70)
color(67, 79, 108).withAlphaComponent(0.7).setStroke()
tile.lineWidth = 3
tile.stroke()
let mark = NSBezierPath()
mark.move(to: NSPoint(x: 280, y: 246))
for point in [NSPoint(x: 280,y: 772), NSPoint(x: 746,y: 772), NSPoint(x: 746,y: 642),
              NSPoint(x: 428,y: 642), NSPoint(x: 428,y: 554), NSPoint(x: 686,y: 554),
              NSPoint(x: 686,y: 426), NSPoint(x: 428,y: 426), NSPoint(x: 428,y: 246)] {
    mark.line(to: point)
}
mark.close()
NSGradient(starting: color(255, 100, 120), ending: color(216, 39, 69))!.draw(in: mark, angle: -90)
let detail = NSBezierPath(roundedRect: NSRect(x: 654, y: 246, width: 92, height: 92), xRadius: 24, yRadius: 24)
color(169, 155, 255).setFill()
detail.fill()
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print(output)
