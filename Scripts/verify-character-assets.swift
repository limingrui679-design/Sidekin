import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift verify-character-assets.swift character-dir\n", stderr)
    exit(2)
}

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let themes = [
    "nova", "mecha", "street", "samurai", "abyss",
    "volcanic", "candy", "wasteland", "phantom", "totem"
]
let stages = ["egg", "hatchling", "juvenile", "ascended", "legendary"]
let expectedNames = Set(themes.flatMap { theme in
    stages.map { "\(theme)-\($0).png" }
})
let fileManager = FileManager.default

struct AssetMask {
    let name: String
    let pixels: [Bool]
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
    fail("expected exactly 50 assets; missing=[\(missing)] unexpected=[\(unexpected)]")
}

let maskSide = 72
let bytesPerRow = maskSide * 4
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
var masks: [String: AssetMask] = [:]
var uniqueFileData = Set<Data>()

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
    guard occupancy > 0.045, occupancy < 0.72 else {
        fail("\(name) has suspicious alpha occupancy \(String(format: "%.3f", occupancy))")
    }
    for corner in [0, maskSide - 1, maskSide * (maskSide - 1), maskSide * maskSide - 1] {
        guard !alphaMask[corner] else {
            fail("\(name) has a non-transparent corner")
        }
    }
    masks[name] = AssetMask(name: name, pixels: alphaMask, occupied: occupied)
}

var maximumWithinLineage: (score: Double, pair: String) = (0, "")
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
            if score >= 0.82 {
                silhouetteViolations.append(
                    "same-lineage \(leftName) / \(rightName), IoU=\(String(format: "%.3f", score))"
                )
            }
        }
    }
}

var maximumAcrossThemes: (score: Double, pair: String) = (0, "")
for stage in stages {
    for leftIndex in themes.indices {
        for rightIndex in themes.indices where rightIndex > leftIndex {
            let leftName = "\(themes[leftIndex])-\(stage).png"
            let rightName = "\(themes[rightIndex])-\(stage).png"
            let score = intersectionOverUnion(masks[leftName]!, masks[rightName]!)
            if score > maximumAcrossThemes.score {
                maximumAcrossThemes = (score, "\(leftName) <> \(rightName)")
            }
            if score >= 0.86 {
                silhouetteViolations.append(
                    "cross-theme \(leftName) / \(rightName), IoU=\(String(format: "%.3f", score))"
                )
            }
        }
    }
}

print("Verified 50 unique 1254x1254 transparent assets.")
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

if !silhouetteViolations.isEmpty {
    fail(silhouetteViolations.joined(separator: "; "))
}
