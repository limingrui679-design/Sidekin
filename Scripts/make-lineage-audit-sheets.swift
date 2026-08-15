import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: swift make-lineage-audit-sheets.swift character-dir output-dir\n", stderr)
    exit(2)
}

let characterDirectory = URL(
    fileURLWithPath: CommandLine.arguments[1],
    isDirectory: true
)
let outputDirectory = URL(
    fileURLWithPath: CommandLine.arguments[2],
    isDirectory: true
)

struct ThemeCatalogEnvelope: Decodable {
    struct Theme: Decodable {
        let id: String
        let displayName: String
        let category: String?
        let tags: [String]?

        var taxonomyLabel: String {
            category ?? (tags ?? []).prefix(2).joined(separator: " · ")
        }
    }

    let themes: [Theme]
}

let projectRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let catalogURL = projectRoot.appendingPathComponent("ArtSources/PET_THEME_CATALOG.json")
guard let catalogData = try? Data(contentsOf: catalogURL),
      let catalog = try? JSONDecoder().decode(ThemeCatalogEnvelope.self, from: catalogData),
      catalog.themes.count == 200
else {
    fputs("Could not decode the 200-theme catalog at \(catalogURL.path)\n", stderr)
    exit(1)
}

let stages: [(id: String, name: String)] = [
    ("egg", "Egg"),
    ("hatchling", "Hatchling"),
    ("juvenile", "Juvenile"),
    ("ascended", "Ascended"),
    ("legendary", "Legendary")
]

let themesPerSheet = 5
let labelWidth: CGFloat = 250
let tileWidth: CGFloat = 250
let rowHeight: CGFloat = 250
let headerHeight: CGFloat = 54
let sheetSize = NSSize(
    width: labelWidth + tileWidth * CGFloat(stages.count),
    height: headerHeight + rowHeight * CGFloat(themesPerSheet)
)

let headerAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 18, weight: .bold),
    .foregroundColor: NSColor.white
]
let nameAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 17, weight: .bold),
    .foregroundColor: NSColor.white
]
let idAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
    .foregroundColor: NSColor(calibratedWhite: 0.72, alpha: 1)
]
let categoryAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 13, weight: .regular),
    .foregroundColor: NSColor(calibratedRed: 0.48, green: 0.76, blue: 1, alpha: 1)
]

try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

let sheetCount = catalog.themes.count / themesPerSheet
for sheetIndex in 0..<sheetCount {
    let sheet = NSImage(size: sheetSize)
    sheet.lockFocus()

    NSColor(calibratedRed: 0.018, green: 0.025, blue: 0.055, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: sheetSize)).fill()

    ("Lineage audit \(String(format: "%02d", sheetIndex + 1)) / \(sheetCount)" as NSString).draw(
        at: NSPoint(x: 18, y: sheetSize.height - 36),
        withAttributes: headerAttributes
    )
    for (stageIndex, stage) in stages.enumerated() {
        let text = stage.name as NSString
        let size = text.size(withAttributes: headerAttributes)
        text.draw(
            at: NSPoint(
                x: labelWidth + CGFloat(stageIndex) * tileWidth + (tileWidth - size.width) / 2,
                y: sheetSize.height - 36
            ),
            withAttributes: headerAttributes
        )
    }

    for row in 0..<themesPerSheet {
        let themeIndex = sheetIndex * themesPerSheet + row
        let theme = catalog.themes[themeIndex]
        let y = sheetSize.height - headerHeight - CGFloat(row + 1) * rowHeight
        let hue = CGFloat(themeIndex) / CGFloat(catalog.themes.count)

        NSColor(calibratedHue: hue, saturation: 0.28, brightness: 0.14, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: y, width: sheetSize.width, height: rowHeight)).fill()
        NSColor(calibratedWhite: 1, alpha: 0.12).setStroke()
        let separator = NSBezierPath()
        separator.move(to: NSPoint(x: 0, y: y))
        separator.line(to: NSPoint(x: sheetSize.width, y: y))
        separator.lineWidth = 1
        separator.stroke()

        (String(format: "%03d  %@", themeIndex + 1, theme.displayName) as NSString).draw(
            in: NSRect(x: 16, y: y + 142, width: labelWidth - 28, height: 52),
            withAttributes: nameAttributes
        )
        (theme.id as NSString).draw(
            in: NSRect(x: 16, y: y + 108, width: labelWidth - 28, height: 24),
            withAttributes: idAttributes
        )
        (theme.taxonomyLabel as NSString).draw(
            in: NSRect(x: 16, y: y + 72, width: labelWidth - 28, height: 42),
            withAttributes: categoryAttributes
        )

        for (stageIndex, stage) in stages.enumerated() {
            let x = labelWidth + CGFloat(stageIndex) * tileWidth
            let cellRect = NSRect(x: x + 5, y: y + 5, width: tileWidth - 10, height: rowHeight - 10)
            NSColor(calibratedWhite: 0.03, alpha: 0.72).setFill()
            NSBezierPath(roundedRect: cellRect, xRadius: 12, yRadius: 12).fill()

            let fileURL = characterDirectory.appendingPathComponent("\(theme.id)-\(stage.id).png")
            guard let image = NSImage(contentsOf: fileURL) else {
                fputs("Missing \(fileURL.path)\n", stderr)
                exit(1)
            }
            let imageArea = NSRect(x: x + 12, y: y + 12, width: tileWidth - 24, height: rowHeight - 24)
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
        }
    }

    sheet.unlockFocus()
    guard let tiff = sheet.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [.compressionFactor: 0.94])
    else {
        fputs("Could not encode audit sheet \(sheetIndex + 1)\n", stderr)
        exit(1)
    }

    let outputURL = outputDirectory.appendingPathComponent(
        "lineage-audit-\(String(format: "%02d", sheetIndex + 1)).png"
    )
    try png.write(to: outputURL, options: .atomic)
    print("Built \(outputURL.path)")
}
