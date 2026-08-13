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

let auraRect = NSRect(x: 164, y: 158, width: 696, height: 696)
NSColor(calibratedRed: 0.16, green: 0.95, blue: 0.93, alpha: 0.17).setFill()
NSBezierPath(ovalIn: auraRect).fill()

// Sidekin's mark is an abstract companion core: a luminous S-shaped orbit
// around a persistent central spark. It represents "side + kin" without
// locking the brand to any one animal, humanoid, machine, or elemental form.
let core = NSBezierPath(ovalIn: NSRect(x: 420, y: 420, width: 184, height: 184))
NSGraphicsContext.saveGraphicsState()
let coreShadow = NSShadow()
coreShadow.shadowColor = NSColor(calibratedRed: 0.15, green: 0.96, blue: 0.93, alpha: 0.65)
coreShadow.shadowBlurRadius = 52
coreShadow.shadowOffset = .zero
coreShadow.set()
NSGradient(colors: [
    NSColor.white,
    NSColor(calibratedRed: 0.27, green: 0.95, blue: 0.91, alpha: 1)
])?.draw(in: core, angle: -55)
NSGraphicsContext.restoreGraphicsState()

let orbit = NSBezierPath()
orbit.move(to: NSPoint(x: 718, y: 754))
orbit.curve(
    to: NSPoint(x: 341, y: 570),
    controlPoint1: NSPoint(x: 552, y: 886),
    controlPoint2: NSPoint(x: 270, y: 780)
)
orbit.curve(
    to: NSPoint(x: 686, y: 442),
    controlPoint1: NSPoint(x: 384, y: 466),
    controlPoint2: NSPoint(x: 624, y: 562)
)
orbit.curve(
    to: NSPoint(x: 301, y: 264),
    controlPoint1: NSPoint(x: 772, y: 294),
    controlPoint2: NSPoint(x: 488, y: 138)
)
orbit.lineWidth = 86
orbit.lineCapStyle = .round
orbit.lineJoinStyle = .round

NSGraphicsContext.saveGraphicsState()
let orbitShadow = NSShadow()
orbitShadow.shadowColor = NSColor(calibratedRed: 0.58, green: 0.34, blue: 1, alpha: 0.60)
orbitShadow.shadowBlurRadius = 46
orbitShadow.shadowOffset = .zero
orbitShadow.set()
NSColor(calibratedRed: 0.72, green: 0.58, blue: 1, alpha: 0.96).setStroke()
orbit.stroke()
NSGraphicsContext.restoreGraphicsState()

let highlight = orbit.copy() as! NSBezierPath
highlight.lineWidth = 28
highlight.lineCapStyle = .round
NSColor.white.withAlphaComponent(0.72).setStroke()
highlight.stroke()

for point in [NSPoint(x: 718, y: 754), NSPoint(x: 301, y: 264)] {
    NSColor(calibratedRed: 1, green: 0.76, blue: 0.30, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: point.x - 28, y: point.y - 28, width: 56, height: 56)).fill()
}

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
