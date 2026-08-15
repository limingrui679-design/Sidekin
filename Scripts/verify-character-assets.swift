import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift verify-character-assets.swift character-dir\n", stderr)
    exit(2)
}

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
struct ThemeCatalogEnvelope: Decodable {
    struct Theme: Decodable {
        let id: String
    }

    let themes: [Theme]
}

let projectRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let catalogURL = projectRoot.appendingPathComponent("ArtSources/PET_THEME_CATALOG.json")
guard let catalogData = try? Data(contentsOf: catalogURL),
      let catalog = try? JSONDecoder().decode(ThemeCatalogEnvelope.self, from: catalogData)
else {
    fputs("Verification failed: cannot decode \(catalogURL.path)\n", stderr)
    exit(1)
}
let themes = catalog.themes.map(\.id)
guard themes.count == 200, Set(themes).count == 200 else {
    fputs("Verification failed: catalog must contain 200 unique theme IDs\n", stderr)
    exit(1)
}
let stages = ["egg", "hatchling", "juvenile", "ascended", "legendary"]
let expectedNames = Set(themes.flatMap { theme in
    stages.map { "\(theme)-\($0).png" }
})
let fileManager = FileManager.default

struct AssetMask {
    let name: String
    let pixels: [Bool]
    let rgba: [UInt8]
    let occupied: Int
}

private func fail(_ message: String) -> Never {
    fputs("Verification failed: \(message)\n", stderr)
    exit(1)
}

private func intersectionOverUnion(_ left: AssetMask, _ right: AssetMask) -> Double {
    var intersection = 0
    var union = 0
    for index in left.pixels.indices {
        let leftValue = left.pixels[index]
        let rightValue = right.pixels[index]
        if leftValue || rightValue { union += 1 }
        if leftValue && rightValue { intersection += 1 }
    }
    return union == 0 ? 1 : Double(intersection) / Double(union)
}

private func appearanceSimilarity(_ left: AssetMask, _ right: AssetMask) -> Double {
    var totalDistance = 0.0
    var comparedPixels = 0

    for index in left.pixels.indices where left.pixels[index] || right.pixels[index] {
        let byteIndex = index * 4
        let redDistance = Double(Int(left.rgba[byteIndex]) - Int(right.rgba[byteIndex]))
        let greenDistance = Double(Int(left.rgba[byteIndex + 1]) - Int(right.rgba[byteIndex + 1]))
        let blueDistance = Double(Int(left.rgba[byteIndex + 2]) - Int(right.rgba[byteIndex + 2]))
        let alphaDistance = abs(
            Double(Int(left.rgba[byteIndex + 3]) - Int(right.rgba[byteIndex + 3]))
        ) / 255
        let colorDistance = sqrt(
            (redDistance * redDistance
                + greenDistance * greenDistance
                + blueDistance * blueDistance)
                / (3 * 255 * 255)
        )

        // RGB catches recolors and internal detail changes; alpha catches
        // holes and appendages that a coarse outer silhouette can hide.
        totalDistance += colorDistance * 0.75 + alphaDistance * 0.25
        comparedPixels += 1
    }

    guard comparedPixels > 0 else { return 1 }
    return max(0, 1 - totalDistance / Double(comparedPixels))
}

let actualNames: Set<String>
do {
    actualNames = Set(
        try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension.lowercased() == "png" }
        .map(\.lastPathComponent)
    )
} catch {
    fail("cannot list asset directory: \(error.localizedDescription)")
}

guard actualNames == expectedNames else {
    let missing = expectedNames.subtracting(actualNames).sorted().joined(separator: ", ")
    let unexpected = actualNames.subtracting(expectedNames).sorted().joined(separator: ", ")
    fail("expected exactly 1,000 assets; missing=[\(missing)] unexpected=[\(unexpected)]")
}

let maskSide = 72
let bytesPerRow = maskSide * 4
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
var masks: [String: AssetMask] = [:]
var uniqueFileData = Set<Data>()
var assetGateViolations: [String] = []

for name in expectedNames.sorted() {
    let url = directory.appendingPathComponent(name)
    guard let data = try? Data(contentsOf: url) else {
        fail("cannot read \(name)")
    }
    guard uniqueFileData.insert(data).inserted else {
        fail("duplicate binary asset found at \(name)")
    }
    guard let image = NSImage(data: data),
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else {
        fail("cannot decode \(name)")
    }
    guard cgImage.width == 1_254, cgImage.height == 1_254 else {
        fail("\(name) is \(cgImage.width)x\(cgImage.height), expected 1254x1254")
    }

    var pixels = [UInt8](repeating: 0, count: maskSide * bytesPerRow)
    guard let context = CGContext(
        data: &pixels,
        width: maskSide,
        height: maskSide,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        fail("cannot create mask context")
    }
    context.interpolationQuality = .high
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: maskSide, height: maskSide))

    var alphaMask = [Bool](repeating: false, count: maskSide * maskSide)
    var occupied = 0
    for index in alphaMask.indices {
        let visible = pixels[index * 4 + 3] > 18
        alphaMask[index] = visible
        if visible { occupied += 1 }
    }

    let occupancy = Double(occupied) / Double(maskSide * maskSide)
    if occupancy <= 0.045 || occupancy >= 0.72 {
        assetGateViolations.append(
            "\(name) has suspicious alpha occupancy \(String(format: "%.3f", occupancy))"
        )
    }
    for corner in [0, maskSide - 1, maskSide * (maskSide - 1), maskSide * maskSide - 1] {
        if alphaMask[corner] {
            assetGateViolations.append("\(name) has a non-transparent corner")
        }
    }
    masks[name] = AssetMask(name: name, pixels: alphaMask, rgba: pixels, occupied: occupied)
}

if !assetGateViolations.isEmpty {
    fail(assetGateViolations.joined(separator: "; "))
}

let withinLineageSilhouetteThreshold = 0.82
let withinLineageAppearanceThreshold = 0.90
let crossThemeSilhouetteThreshold = 0.86
let crossThemeAppearanceThreshold = 0.92

var maximumWithinLineage: (score: Double, pair: String) = (0, "")
var maximumWithinLineageAppearance: (score: Double, pair: String) = (0, "")
var silhouetteViolations: [String] = []
for theme in themes {
    for leftIndex in stages.indices {
        for rightIndex in stages.indices where rightIndex > leftIndex {
            let leftName = "\(theme)-\(stages[leftIndex]).png"
            let rightName = "\(theme)-\(stages[rightIndex]).png"
            let score = intersectionOverUnion(masks[leftName]!, masks[rightName]!)
            if score > maximumWithinLineage.score {
                maximumWithinLineage = (score, "\(leftName) <> \(rightName)")
            }
            guard score >= withinLineageSilhouetteThreshold else { continue }
            let appearance = appearanceSimilarity(masks[leftName]!, masks[rightName]!)
            if appearance > maximumWithinLineageAppearance.score {
                maximumWithinLineageAppearance = (
                    appearance,
                    "\(leftName) <> \(rightName), silhouette=\(String(format: "%.3f", score))"
                )
            }
            if appearance >= withinLineageAppearanceThreshold {
                silhouetteViolations.append(
                    "same-lineage \(leftName) / \(rightName), silhouette=\(String(format: "%.3f", score)), appearance=\(String(format: "%.3f", appearance))"
                )
            }
        }
    }
}

var maximumAcrossThemes: (score: Double, pair: String) = (0, "")
var maximumAcrossThemesAppearance: (score: Double, pair: String) = (0, "")
for stage in stages {
    for leftIndex in themes.indices {
        for rightIndex in themes.indices where rightIndex > leftIndex {
            let leftName = "\(themes[leftIndex])-\(stage).png"
            let rightName = "\(themes[rightIndex])-\(stage).png"
            let score = intersectionOverUnion(masks[leftName]!, masks[rightName]!)
            if score > maximumAcrossThemes.score {
                maximumAcrossThemes = (score, "\(leftName) <> \(rightName)")
            }
            guard score >= crossThemeSilhouetteThreshold else { continue }
            let appearance = appearanceSimilarity(masks[leftName]!, masks[rightName]!)
            if appearance > maximumAcrossThemesAppearance.score {
                maximumAcrossThemesAppearance = (
                    appearance,
                    "\(leftName) <> \(rightName), silhouette=\(String(format: "%.3f", score))"
                )
            }
            if appearance >= crossThemeAppearanceThreshold {
                silhouetteViolations.append(
                    "cross-theme \(leftName) / \(rightName), silhouette=\(String(format: "%.3f", score)), appearance=\(String(format: "%.3f", appearance))"
                )
            }
        }
    }
}

print("Verified 1,000 unique 1254x1254 transparent assets across 200 complete themes.")
print(
    "Highest within-lineage silhouette IoU: "
        + String(format: "%.3f", maximumWithinLineage.score)
        + " (\(maximumWithinLineage.pair))"
)

print(
    "Highest same-stage cross-theme silhouette IoU: "
        + String(format: "%.3f", maximumAcrossThemes.score)
        + " (\(maximumAcrossThemes.pair))"
)

print(
    "Highest within-lineage appearance similarity among high-IoU candidates: "
        + String(format: "%.3f", maximumWithinLineageAppearance.score)
        + " (\(maximumWithinLineageAppearance.pair))"
)

print(
    "Highest cross-theme appearance similarity among high-IoU candidates: "
        + String(format: "%.3f", maximumAcrossThemesAppearance.score)
        + " (\(maximumAcrossThemesAppearance.pair))"
)

if !silhouetteViolations.isEmpty {
    fail(silhouetteViolations.joined(separator: "; "))
}
