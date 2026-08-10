import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: swift make-character-roster.swift character-dir output.png\n", stderr)
    exit(2)
}

let characterDirectory = URL(
    fileURLWithPath: CommandLine.arguments[1],
    isDirectory: true
)
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let themes: [(id: String, name: String)] = [
    ("nova", "Nova Arena"),
    ("mecha", "Vanguard Mecha"),
    ("street", "Street Brawl"),
    ("samurai", "Sakura Blade"),
    ("abyss", "Abyssal Tidehunter"),
    ("volcanic", "Molten Tyrant"),
    ("candy", "Candy Carnival"),
    ("wasteland", "Wasteland Salvager"),
    ("phantom", "Phantom Veil"),
    ("totem", "Verdant Totem")
]
let stages: [(id: String, name: String)] = [
    ("egg", "Core Egg"),
    ("hatchling", "First Spark"),
    ("juvenile", "Shifting Form"),
    ("ascended", "Ascension"),
    ("legendary", "Crown Form")
]

let tileWidth: CGFloat = 270
let tileHeight: CGFloat = 270
let labelHeight: CGFloat = 34
let sheetSize = NSSize(
    width: tileWidth * CGFloat(stages.count),
    height: tileHeight * CGFloat(themes.count)
)
let sheet = NSImage(size: sheetSize)

sheet.lockFocus()
NSColor(calibratedRed: 0.018, green: 0.025, blue: 0.055, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: sheetSize)).fill()

let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 12, weight: .bold),
    .foregroundColor: NSColor.white
]
let subtitleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 11, weight: .medium),
    .foregroundColor: NSColor(calibratedWhite: 0.72, alpha: 1)
]

for (themeIndex, theme) in themes.enumerated() {
    for (stageIndex, stage) in stages.enumerated() {
        let x = CGFloat(stageIndex) * tileWidth
        let y = sheetSize.height - CGFloat(themeIndex + 1) * tileHeight
        let tileRect = NSRect(x: x + 4, y: y + 4, width: tileWidth - 8, height: tileHeight - 8)

        let hue = CGFloat(themeIndex) / CGFloat(themes.count)
        NSColor(calibratedHue: hue, saturation: 0.35, brightness: 0.17, alpha: 1).setFill()
        NSBezierPath(roundedRect: tileRect, xRadius: 14, yRadius: 14).fill()
        NSColor(calibratedWhite: 1, alpha: 0.10).setStroke()
        let border = NSBezierPath(roundedRect: tileRect, xRadius: 14, yRadius: 14)
        border.lineWidth = 1
        border.stroke()

        let fileURL = characterDirectory.appendingPathComponent("\(theme.id)-\(stage.id).png")
        guard let image = NSImage(contentsOf: fileURL) else {
            fputs("Missing \(fileURL.path)\n", stderr)
            exit(1)
        }

        let imageArea = NSRect(
            x: x + 14,
            y: y + labelHeight + 5,
            width: tileWidth - 28,
            height: tileHeight - labelHeight - 16
        )
        let sourceSize = image.size
        let scale = min(imageArea.width / sourceSize.width, imageArea.height / sourceSize.height)
        let destination = NSRect(
            x: imageArea.midX - sourceSize.width * scale / 2,
            y: imageArea.midY - sourceSize.height * scale / 2,
            width: sourceSize.width * scale,
            height: sourceSize.height * scale
        )
        image.draw(
            in: destination,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )

        let title = "\(theme.name) · \(stage.name)" as NSString
        title.draw(
            at: NSPoint(x: x + 14, y: y + 16),
            withAttributes: titleAttributes
        )
        let indexText = String(format: "%02d", themeIndex * stages.count + stageIndex + 1) as NSString
        let indexSize = indexText.size(withAttributes: subtitleAttributes)
        indexText.draw(
            at: NSPoint(x: x + tileWidth - indexSize.width - 14, y: y + 17),
            withAttributes: subtitleAttributes
        )
    }
}

sheet.unlockFocus()

guard let tiff = sheet.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(
        using: .png,
        properties: [.compressionFactor: 0.92]
      )
else {
    fputs("Could not encode roster\n", stderr)
    exit(1)
}

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try png.write(to: outputURL, options: .atomic)
print("Built \(outputURL.path)")
