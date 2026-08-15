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

func drawCharacter(
    _ theme: String,
    _ stage: String,
    centeredAt center: NSPoint,
    size: NSSize,
    alpha: CGFloat = 1
) {
    let source = image(theme, stage)
    let scale = min(size.width / source.size.width, size.height / source.size.height)
    let destination = NSRect(
        x: center.x - source.size.width * scale / 2,
        y: center.y - source.size.height * scale / 2,
        width: source.size.width * scale,
        height: source.size.height * scale
    )
    source.draw(
        in: destination,
        from: .zero,
        operation: .sourceOver,
        fraction: alpha,
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

let heroSourceURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("ArtSources/READMEHero/hero-dynamic-source.png")
guard let heroSource = NSImage(contentsOf: heroSourceURL) else {
    fputs("Missing dynamic README hero source: \(heroSourceURL.path)\n", stderr)
    exit(1)
}
let heroSize = NSSize(width: 1_600, height: 760)
let hero = NSImage(size: heroSize)
hero.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high
heroSource.draw(
    in: NSRect(origin: .zero, size: heroSize),
    from: NSRect(origin: .zero, size: heroSource.size),
    operation: .copy,
    fraction: 1,
    respectFlipped: true,
    hints: [.interpolation: NSImageInterpolation.high]
)
hero.unlockFocus()
try saveJPEG(hero, named: "hero.jpg", quality: 0.94)

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
("Nonhuman heroes, mythic creatures, gods, animals, and mecha." as NSString).draw(
    at: NSPoint(x: 62, y: 872),
    withAttributes: subtitle
)

let catalogEntries: [(String, String, String, NSColor)] = [
    ("astral-vowkeeper", "SACRED", "Vowkeeper", gold),
    ("moonveil-oracle", "MYSTERIOUS", "Moonveil Oracle", violet),
    ("dreamglass-fencer", "EXQUISITE", "Dreamglass", cyan),
    ("celestial-garuda", "WINGED HERO", "Garuda", gold),
    ("roseglass-fennec", "CUTE BEAST", "Roseglass Fennec", violet),
    ("glacier-sky-dragon", "MYTHIC", "Sky Dragon", cyan),
    ("sacred-lotus-avatar", "DIVINE", "Lotus Avatar", gold),
    ("eclipse-wing-oracle", "GOTHIC", "Eclipse Oracle", violet),
    ("neon-raptor-racer", "NEON MECHA", "Raptor Racer", cyan),
    ("prism-samurai-frame", "ARENA MECHA", "Prism Frame", gold)
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

// MARK: Expanded showcase

let showcaseSize = NSSize(width: 1_600, height: 1_330)
let showcaseImage = NSImage(size: showcaseSize)
showcaseImage.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high
fillBackground(NSRect(origin: .zero, size: showcaseSize))
("TWENTY WAYS TO EXIST." as NSString).draw(at: NSPoint(x: 62, y: 1_250), withAttributes: eyebrow)
("A broad sample from the continuous tag-based built-in catalog." as NSString).draw(
    at: NSPoint(x: 62, y: 1_202),
    withAttributes: subtitle
)

let showcaseEntries: [(String, String, String, NSColor)] = [
    ("astral-vowkeeper", "SACRED", "Vowkeeper", cyan),
    ("moonveil-oracle", "MYSTERIOUS", "Moonveil Oracle", gold),
    ("dreamglass-fencer", "EXQUISITE", "Dreamglass", violet),
    ("storm-mask-runner", "HEROIC", "Storm Runner", cyan),
    ("candy-star-idol", "CUTE", "Candy Star", gold),
    ("celestial-garuda", "WINGED HERO", "Garuda", violet),
    ("glacier-sky-dragon", "MYTHIC", "Sky Dragon", cyan),
    ("roseglass-fennec", "CUTE BEAST", "Roseglass Fennec", gold),
    ("cosmic-orca", "MAJESTIC", "Cosmic Orca", violet),
    ("spectral-axolotl", "DREAMLIKE", "Spectral Axolotl", cyan),
    ("dawnwheel-seraph", "DIVINE", "Dawnwheel Seraph", gold),
    ("sacred-lotus-avatar", "SACRED", "Lotus Avatar", violet),
    ("jade-comet-empress", "REGAL", "Comet Empress", cyan),
    ("void-gate-keeper", "DARK DIVINE", "Void Keeper", gold),
    ("eclipse-wing-oracle", "GOTHIC", "Eclipse Oracle", violet),
    ("neon-raptor-racer", "NEON MECHA", "Raptor Racer", cyan),
    ("prism-samurai-frame", "ARENA MECHA", "Prism Frame", gold),
    ("lunar-rabbit-rover", "CUTE MECHA", "Rabbit Rover", violet),
    ("stealth-manta-jet", "STEALTH MECHA", "Manta Jet", cyan),
    ("solar-wyrm-mech", "REGAL MECHA", "Solar Wyrm", gold)
]
let showcaseColumns = 5
let showcaseCardWidth: CGFloat = 286
let showcaseCardHeight: CGFloat = 250
let showcaseGutter: CGFloat = 20
let showcaseStartX: CGFloat = 45
let showcaseStartY: CGFloat = 905

for (index, entry) in showcaseEntries.enumerated() {
    let column = index % showcaseColumns
    let row = index / showcaseColumns
    let rect = NSRect(
        x: showcaseStartX + CGFloat(column) * (showcaseCardWidth + showcaseGutter),
        y: showcaseStartY - CGFloat(row) * (showcaseCardHeight + 18),
        width: showcaseCardWidth,
        height: showcaseCardHeight
    )
    panel.setFill()
    NSBezierPath(roundedRect: rect, xRadius: 24, yRadius: 24).fill()
    entry.3.withAlphaComponent(0.24).setStroke()
    let border = NSBezierPath(roundedRect: rect, xRadius: 24, yRadius: 24)
    border.lineWidth = 2
    border.stroke()
    drawCharacter(
        entry.0,
        "legendary",
        in: NSRect(x: rect.minX + 8, y: rect.minY + 58, width: rect.width - 16, height: rect.height - 64)
    )
    (entry.1 as NSString).draw(at: NSPoint(x: rect.minX + 16, y: rect.minY + 38), withAttributes: cardCaption)
    (entry.2 as NSString).draw(
        in: NSRect(x: rect.minX + 16, y: rect.minY + 10, width: rect.width - 32, height: 28),
        withAttributes: cardTitle
    )
}
showcaseImage.unlockFocus()
try saveJPEG(showcaseImage, named: "showcase-20.jpg", quality: 0.88)

// MARK: All 200 lineage thumbnails

struct CatalogEnvelope: Decodable {
    struct Theme: Decodable {
        let id: String
        let displayName: String
    }

    let themes: [Theme]
}

let projectRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let catalogURL = projectRoot.appendingPathComponent("ArtSources/PET_THEME_CATALOG.json")
guard let catalogData = try? Data(contentsOf: catalogURL),
      let catalog = try? JSONDecoder().decode(CatalogEnvelope.self, from: catalogData),
      catalog.themes.count == 200
else {
    fputs("Could not read 200-theme catalog for README overview.\n", stderr)
    exit(1)
}

let allSize = NSSize(width: 2_000, height: 4_210)
let allImage = NSImage(size: allSize)
allImage.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high
fillBackground(NSRect(origin: .zero, size: allSize))
("ALL 200 LINEAGES." as NSString).draw(at: NSPoint(x: 64, y: 4_130), withAttributes: eyebrow)
("One final form from every built-in evolution path." as NSString).draw(
    at: NSPoint(x: 64, y: 4_082),
    withAttributes: subtitle
)

let allColumns = 10
let allRows = 20
let allCellWidth: CGFloat = 190
let allCellHeight: CGFloat = 195
let allStartX: CGFloat = 50
let allStartY: CGFloat = 3_850
let tinyName: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
    .foregroundColor: NSColor.white
]
for (index, theme) in catalog.themes.enumerated() {
    let column = index % allColumns
    let row = index / allColumns
    let rect = NSRect(
        x: allStartX + CGFloat(column) * allCellWidth,
        y: allStartY - CGFloat(row) * allCellHeight,
        width: allCellWidth - 8,
        height: allCellHeight - 8
    )
    let rowColor = [cyan, violet, gold][row % 3]
    panel.withAlphaComponent(0.78).setFill()
    NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16).fill()
    rowColor.withAlphaComponent(0.18).setStroke()
    let border = NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16)
    border.lineWidth = 1.2
    border.stroke()
    drawCharacter(
        theme.id,
        "legendary",
        in: NSRect(x: rect.minX + 5, y: rect.minY + 28, width: rect.width - 10, height: rect.height - 32)
    )
    let ordinal = String(format: "%03d", index + 1)
    (ordinal as NSString).draw(at: NSPoint(x: rect.minX + 9, y: rect.minY + 9), withAttributes: cardCaption)
    (theme.displayName as NSString).draw(
        in: NSRect(x: rect.minX + 47, y: rect.minY + 8, width: rect.width - 54, height: 20),
        withAttributes: tinyName
    )
}
allImage.unlockFocus()
try saveJPEG(allImage, named: "all-200.jpg", quality: 0.9)

print("Built README media in \(outputDirectory.path)")
