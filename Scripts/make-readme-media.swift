import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: swift make-readme-media.swift character-dir output-dir\n", stderr)
    exit(2)
}

let characterDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let navy = NSColor(calibratedRed: 0.022, green: 0.028, blue: 0.075, alpha: 1)
let panel = NSColor(calibratedRed: 0.055, green: 0.07, blue: 0.15, alpha: 0.96)
let cyan = NSColor(calibratedRed: 0.22, green: 0.93, blue: 0.91, alpha: 1)
let violet = NSColor(calibratedRed: 0.63, green: 0.42, blue: 1, alpha: 1)
let gold = NSColor(calibratedRed: 1, green: 0.73, blue: 0.27, alpha: 1)
let muted = NSColor(calibratedWhite: 0.73, alpha: 1)

let title: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 92, weight: .black),
    .foregroundColor: NSColor.white,
    .kern: -2
]
let subtitle: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 29, weight: .medium),
    .foregroundColor: muted
]
let eyebrow: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: 21, weight: .bold),
    .foregroundColor: cyan,
    .kern: 2.5
]
let cardTitle: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 23, weight: .bold),
    .foregroundColor: NSColor.white
]
let cardCaption: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: 15, weight: .medium),
    .foregroundColor: muted
]

func fillBackground(_ rect: NSRect) {
    navy.setFill()
    NSBezierPath(rect: rect).fill()
    NSGradient(colors: [
        NSColor(calibratedRed: 0.17, green: 0.06, blue: 0.35, alpha: 0.85),
        NSColor(calibratedRed: 0.02, green: 0.28, blue: 0.34, alpha: 0.38),
        navy
    ])?.draw(in: rect, angle: -20)
}

func glow(at center: NSPoint, radius: CGFloat, color: NSColor) {
    let colors = [color.withAlphaComponent(0.26), color.withAlphaComponent(0)]
    NSGradient(colors: colors)?.draw(
        fromCenter: center,
        radius: 0,
        toCenter: center,
        radius: radius,
        options: []
    )
}

func image(_ theme: String, _ stage: String) -> NSImage {
    let url = characterDirectory.appendingPathComponent("\(theme)-\(stage).png")
    guard let result = NSImage(contentsOf: url) else {
        fputs("Missing README character asset: \(url.path)\n", stderr)
        exit(1)
    }
    return result
}

func drawCharacter(_ theme: String, _ stage: String, in rect: NSRect) {
    let source = image(theme, stage)
    let scale = min(rect.width / source.size.width, rect.height / source.size.height)
    let destination = NSRect(
        x: rect.midX - source.size.width * scale / 2,
        y: rect.midY - source.size.height * scale / 2,
        width: source.size.width * scale,
        height: source.size.height * scale
    )
    source.draw(
        in: destination,
        from: .zero,
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.high]
    )
}

func saveJPEG(_ image: NSImage, named fileName: String, quality: CGFloat = 0.88) throws {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality])
    else {
        throw NSError(domain: "SidekinReadmeMedia", code: 1)
    }
    try data.write(to: outputDirectory.appendingPathComponent(fileName), options: .atomic)
}

func drawPill(_ text: String, at origin: NSPoint, color: NSColor) -> CGFloat {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
        .foregroundColor: NSColor.white
    ]
    let value = text as NSString
    let size = value.size(withAttributes: attributes)
    let rect = NSRect(x: origin.x, y: origin.y, width: size.width + 34, height: 42)
    color.withAlphaComponent(0.24).setFill()
    NSBezierPath(roundedRect: rect, xRadius: 21, yRadius: 21).fill()
    color.withAlphaComponent(0.72).setStroke()
    let border = NSBezierPath(roundedRect: rect, xRadius: 21, yRadius: 21)
    border.lineWidth = 1.4
    border.stroke()
    value.draw(at: NSPoint(x: rect.minX + 17, y: rect.minY + 10), withAttributes: attributes)
    return rect.width
}

// MARK: Hero

let heroSize = NSSize(width: 1_600, height: 760)
let hero = NSImage(size: heroSize)
hero.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high
fillBackground(NSRect(origin: .zero, size: heroSize))
glow(at: NSPoint(x: 1_200, y: 380), radius: 480, color: cyan)
glow(at: NSPoint(x: 980, y: 300), radius: 340, color: violet)

("CODE. CARE. EVOLVE." as NSString).draw(at: NSPoint(x: 92, y: 610), withAttributes: eyebrow)
("Sidekin" as NSString).draw(at: NSPoint(x: 84, y: 470), withAttributes: title)
("A local-first macOS companion that grows\nwith your Codex workflow." as NSString).draw(
    in: NSRect(x: 92, y: 360, width: 590, height: 86),
    withAttributes: subtitle
)
var pillX: CGFloat = 92
for (label, color) in [("100 lineages", cyan), ("500 forms", violet), ("local-first", gold)] {
    pillX += drawPill(label, at: NSPoint(x: pillX, y: 280), color: color) + 12
}

let heroCharacters: [(String, NSRect, NSColor)] = [
    ("mecha", NSRect(x: 780, y: 155, width: 390, height: 500), violet),
    ("nova", NSRect(x: 1_010, y: 105, width: 410, height: 520), cyan),
    ("walking-treehouse", NSRect(x: 1_265, y: 140, width: 320, height: 430), gold)
]
for (theme, rect, color) in heroCharacters {
    glow(at: NSPoint(x: rect.midX, y: rect.midY), radius: rect.width * 0.6, color: color)
    drawCharacter(theme, "legendary", in: rect)
}
hero.unlockFocus()
try saveJPEG(hero, named: "hero.jpg", quality: 0.9)

// MARK: Five-stage evolution

let evolutionSize = NSSize(width: 1_600, height: 940)
let evolution = NSImage(size: evolutionSize)
evolution.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high
fillBackground(NSRect(origin: .zero, size: evolutionSize))
("FIVE STAGES. ONE IDENTITY." as NSString).draw(at: NSPoint(x: 70, y: 860), withAttributes: eyebrow)
("Every lineage evolves without losing its visual DNA." as NSString).draw(
    at: NSPoint(x: 70, y: 812),
    withAttributes: subtitle
)

let stages = ["egg", "hatchling", "juvenile", "ascended", "legendary"]
let stageLabels = ["CORE EGG", "FIRST SPARK", "SHIFTING FORM", "ASCENSION", "CROWN FORM"]
let rows: [(id: String, name: String, color: NSColor)] = [
    ("nova", "Nova Circuit", cyan),
    ("mecha", "Vanguard Mecha", violet),
    ("walking-treehouse", "Walking Treehouse", gold)
]
let labelWidth: CGFloat = 245
let cellWidth: CGFloat = 250
let rowHeight: CGFloat = 230
let gridLeft: CGFloat = 62
let gridTop: CGFloat = 760

for index in stages.indices {
    (stageLabels[index] as NSString).draw(
        in: NSRect(x: gridLeft + labelWidth + CGFloat(index) * cellWidth, y: gridTop, width: cellWidth, height: 28),
        withAttributes: cardCaption
    )
}
for (rowIndex, row) in rows.enumerated() {
    let y = gridTop - 64 - CGFloat(rowIndex + 1) * rowHeight
    (row.name as NSString).draw(
        in: NSRect(x: gridLeft, y: y + 120, width: labelWidth - 18, height: 60),
        withAttributes: cardTitle
    )
    ("AUDITED LINEAGE" as NSString).draw(
        at: NSPoint(x: gridLeft, y: y + 88),
        withAttributes: cardCaption
    )
    for (stageIndex, stage) in stages.enumerated() {
        let rect = NSRect(
            x: gridLeft + labelWidth + CGFloat(stageIndex) * cellWidth + 8,
            y: y + 4,
            width: cellWidth - 16,
            height: rowHeight - 12
        )
        panel.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 24, yRadius: 24).fill()
        row.color.withAlphaComponent(0.18).setStroke()
        let border = NSBezierPath(roundedRect: rect, xRadius: 24, yRadius: 24)
        border.lineWidth = 2
        border.stroke()
        drawCharacter(row.id, stage, in: rect.insetBy(dx: 10, dy: 10))
    }
}
evolution.unlockFocus()
try saveJPEG(evolution, named: "evolution.jpg", quality: 0.88)

// MARK: Catalog

let catalogSize = NSSize(width: 1_600, height: 1_000)
let catalogImage = NSImage(size: catalogSize)
catalogImage.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high
fillBackground(NSRect(origin: .zero, size: catalogSize))
("NOT JUST ANIMALS." as NSString).draw(at: NSPoint(x: 62, y: 920), withAttributes: eyebrow)
("Creatures, mecha, gods, artifacts, worlds, and living systems." as NSString).draw(
    at: NSPoint(x: 62, y: 872),
    withAttributes: subtitle
)

let catalogEntries: [(String, String, String, NSColor)] = [
    ("manticore", "MYTHIC", "Manticore", gold),
    ("mecha", "MECHA", "Vanguard", violet),
    ("moon-lotus", "FLORA", "Moon Lotus", cyan),
    ("halite-crown", "MINERAL", "Halite Crown", gold),
    ("celestial-musicbox", "ARTIFACT", "Musicbox", violet),
    ("ramen-nebula", "ALCHEMY", "Ramen Nebula", cyan),
    ("cyclone-dancer", "ELEMENTAL", "Cyclone", gold),
    ("event-horizon", "COSMIC", "Event Horizon", violet),
    ("sky-temple", "ARCHITECTURE", "Sky Temple", cyan),
    ("slime-parliament", "COLLECTIVE", "Parliament", gold)
]
let columns = 5
let cardWidth: CGFloat = 286
let cardHeight: CGFloat = 350
let gutter: CGFloat = 20
let startX: CGFloat = 45
let startY: CGFloat = 465

for (index, entry) in catalogEntries.enumerated() {
    let column = index % columns
    let row = index / columns
    let rect = NSRect(
        x: startX + CGFloat(column) * (cardWidth + gutter),
        y: startY - CGFloat(row) * (cardHeight + 24),
        width: cardWidth,
        height: cardHeight
    )
    panel.setFill()
    NSBezierPath(roundedRect: rect, xRadius: 26, yRadius: 26).fill()
    entry.3.withAlphaComponent(0.24).setStroke()
    let border = NSBezierPath(roundedRect: rect, xRadius: 26, yRadius: 26)
    border.lineWidth = 2
    border.stroke()
    drawCharacter(entry.0, "legendary", in: NSRect(x: rect.minX + 10, y: rect.minY + 70, width: rect.width - 20, height: rect.height - 80))
    (entry.1 as NSString).draw(at: NSPoint(x: rect.minX + 18, y: rect.minY + 48), withAttributes: cardCaption)
    (entry.2 as NSString).draw(
        in: NSRect(x: rect.minX + 18, y: rect.minY + 16, width: rect.width - 36, height: 30),
        withAttributes: cardTitle
    )
}
catalogImage.unlockFocus()
try saveJPEG(catalogImage, named: "catalog.jpg", quality: 0.88)

print("Built README media in \(outputDirectory.path)")
