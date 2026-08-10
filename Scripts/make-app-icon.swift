import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift make-app-icon.swift output.png\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let canvas = NSSize(width: 1_024, height: 1_024)
let image = NSImage(size: canvas)

image.lockFocus()

NSGraphicsContext.current?.imageInterpolation = .high

let outer = NSRect(x: 36, y: 36, width: 952, height: 952)
let background = NSBezierPath(roundedRect: outer, xRadius: 226, yRadius: 226)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.36)
shadow.shadowBlurRadius = 52
shadow.shadowOffset = NSSize(width: 0, height: -18)
shadow.set()
NSColor(calibratedRed: 0.07, green: 0.07, blue: 0.16, alpha: 1).setFill()
background.fill()
NSGraphicsContext.restoreGraphicsState()

background.addClip()
NSGradient(colors: [
    NSColor(calibratedRed: 0.15, green: 0.08, blue: 0.34, alpha: 1),
    NSColor(calibratedRed: 0.03, green: 0.46, blue: 0.58, alpha: 1)
])?.draw(in: background, angle: -48)

for (center, radius, alpha) in [
    (NSPoint(x: 230, y: 720), CGFloat(18), CGFloat(0.82)),
    (NSPoint(x: 820, y: 690), CGFloat(13), CGFloat(0.76)),
    (NSPoint(x: 185, y: 360), CGFloat(10), CGFloat(0.68)),
    (NSPoint(x: 845, y: 340), CGFloat(18), CGFloat(0.72))
] {
    NSColor(calibratedRed: 0.15, green: 0.95, blue: 0.88, alpha: alpha).setFill()
    NSBezierPath(ovalIn: NSRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
    )).fill()
}

let auraRect = NSRect(x: 194, y: 150, width: 636, height: 690)
NSColor(calibratedRed: 0.16, green: 0.95, blue: 0.93, alpha: 0.20).setFill()
NSBezierPath(ovalIn: auraRect).fill()

let eggRect = NSRect(x: 274, y: 188, width: 476, height: 612)
let egg = NSBezierPath(ovalIn: eggRect)

NSGraphicsContext.saveGraphicsState()
let eggShadow = NSShadow()
eggShadow.shadowColor = NSColor(calibratedRed: 0.0, green: 0.9, blue: 1.0, alpha: 0.44)
eggShadow.shadowBlurRadius = 48
eggShadow.shadowOffset = NSSize(width: 0, height: -8)
eggShadow.set()
NSGradient(colors: [
    NSColor(calibratedRed: 0.74, green: 1.0, blue: 0.94, alpha: 1),
    NSColor(calibratedRed: 0.31, green: 0.73, blue: 0.92, alpha: 1)
])?.draw(in: egg, angle: -78)
NSGraphicsContext.restoreGraphicsState()

egg.lineWidth = 18
NSColor.white.withAlphaComponent(0.84).setStroke()
egg.stroke()

let leftLeaf = NSBezierPath(ovalIn: NSRect(x: 386, y: 748, width: 142, height: 94))
let rightLeaf = NSBezierPath(ovalIn: NSRect(x: 500, y: 748, width: 142, height: 94))
NSColor(calibratedRed: 0.36, green: 0.88, blue: 0.45, alpha: 1).setFill()
leftLeaf.fill()
NSColor(calibratedRed: 0.49, green: 0.93, blue: 0.53, alpha: 1).setFill()
rightLeaf.fill()

let stem = NSBezierPath(roundedRect: NSRect(x: 494, y: 704, width: 36, height: 100), xRadius: 18, yRadius: 18)
NSColor(calibratedRed: 0.11, green: 0.54, blue: 0.30, alpha: 1).setFill()
stem.fill()

let eyeColor = NSColor(calibratedRed: 0.05, green: 0.13, blue: 0.27, alpha: 1)
for x in [365.0, 563.0] {
    eyeColor.setFill()
    NSBezierPath(ovalIn: NSRect(x: x, y: 425, width: 98, height: 112)).fill()
    NSColor.white.withAlphaComponent(0.96).setFill()
    NSBezierPath(ovalIn: NSRect(x: x + 19, y: 496, width: 30, height: 30)).fill()
}

let mouth = NSBezierPath(roundedRect: NSRect(x: 477, y: 360, width: 70, height: 28), xRadius: 14, yRadius: 14)
eyeColor.setFill()
mouth.fill()

let crack = NSBezierPath()
crack.move(to: NSPoint(x: 518, y: 676))
crack.line(to: NSPoint(x: 486, y: 595))
crack.line(to: NSPoint(x: 534, y: 556))
crack.line(to: NSPoint(x: 500, y: 490))
crack.lineWidth = 14
crack.lineCapStyle = .round
crack.lineJoinStyle = .round
NSColor.white.withAlphaComponent(0.84).setStroke()
crack.stroke()

image.unlockFocus()

guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fputs("Could not render app icon.\n", stderr)
    exit(1)
}

let bitmap = NSBitmapImageRep(cgImage: cgImage)
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not encode app icon.\n", stderr)
    exit(1)
}

try png.write(to: outputURL, options: .atomic)
