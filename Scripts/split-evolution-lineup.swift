import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 5 else {
    fputs(
        "Usage: swift split-evolution-lineup.swift lineup.png theme art-source-dir resource-dir\n",
        stderr
    )
    exit(2)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let theme = CommandLine.arguments[2]
let sourceDirectory = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
let resourceDirectory = URL(fileURLWithPath: CommandLine.arguments[4], isDirectory: true)
let stages = ["egg", "hatchling", "juvenile", "ascended", "legendary"]
let outputSide = 1_254

private struct PixelComponent {
    let label: Int32
    var area: Int
    var minimumX: Int
    var maximumX: Int
    var minimumY: Int
    var maximumY: Int
    var sumX: Int64
    var sumY: Int64
    var sumRed: Int64
    var sumGreen: Int64
    var sumBlue: Int64

    var centerX: Double { Double(sumX) / Double(area) }
    var centerY: Double { Double(sumY) / Double(area) }

    var isMagentaBackdropArtifact: Bool {
        let red = Double(sumRed) / Double(area)
        let green = Double(sumGreen) / Double(area)
        let blue = Double(sumBlue) / Double(area)
        return red > 210 && blue > 210 && green < 55 && abs(red - blue) < 42
    }
}

private func smoothstep(_ edge0: Double, _ edge1: Double, _ value: Double) -> Double {
    let t = min(1, max(0, (value - edge0) / (edge1 - edge0)))
    return t * t * (3 - 2 * t)
}

private struct BackgroundColor {
    var red: Double
    var green: Double
    var blue: Double
    var strictTolerance: Double
    var softTolerance: Double
}

private func colorDistance(
    red: Double,
    green: Double,
    blue: Double,
    background: BackgroundColor
) -> Double {
    sqrt(
        pow(red - background.red, 2)
            + pow(green - background.green, 2)
            + pow(blue - background.blue, 2)
    )
}

private func inferredBorderBackground(
    pixels: [UInt8],
    width: Int,
    height: Int
) -> BackgroundColor {
    let bucketCount = 8 * 8 * 8
    var counts = [Int](repeating: 0, count: bucketCount)
    var redSums = [Double](repeating: 0, count: bucketCount)
    var greenSums = [Double](repeating: 0, count: bucketCount)
    var blueSums = [Double](repeating: 0, count: bucketCount)
    var samples: [(Double, Double, Double, Int)] = []

    func add(_ x: Int, _ y: Int) {
        let index = (y * width + x) * 4
        guard pixels[index + 3] > 127 else { return }
        let red = Double(pixels[index]) / 255
        let green = Double(pixels[index + 1]) / 255
        let blue = Double(pixels[index + 2]) / 255
        let bucket = min(7, Int(red * 8)) * 64
            + min(7, Int(green * 8)) * 8
            + min(7, Int(blue * 8))
        counts[bucket] += 1
        redSums[bucket] += red
        greenSums[bucket] += green
        blueSums[bucket] += blue
        samples.append((red, green, blue, bucket))
    }

    for x in 0..<width {
        add(x, 0)
        if height > 1 { add(x, height - 1) }
    }
    if height > 2 {
        for y in 1..<(height - 1) {
            add(0, y)
            if width > 1 { add(width - 1, y) }
        }
    }

    guard let dominant = counts.indices.max(by: { counts[$0] < counts[$1] }),
          counts[dominant] >= max(8, samples.count / 8)
    else {
        return BackgroundColor(
            red: 1,
            green: 0,
            blue: 1,
            strictTolerance: 0.07,
            softTolerance: 0.30
        )
    }
    let count = Double(counts[dominant])
    let red = redSums[dominant] / count
    let green = greenSums[dominant] / count
    let blue = blueSums[dominant] / count
    let variance = samples.lazy
        .filter { $0.3 == dominant }
        .map { pow($0.0 - red, 2) + pow($0.1 - green, 2) + pow($0.2 - blue, 2) }
        .reduce(0, +) / count
    let deviation = sqrt(variance)
    return BackgroundColor(
        red: red,
        green: green,
        blue: blue,
        strictTolerance: min(0.14, max(0.055, deviation * 3 + 0.035)),
        softTolerance: min(0.34, max(0.24, deviation * 5 + 0.22))
    )
}

private func connectedBackgroundMask(
    pixels: [UInt8],
    width: Int,
    height: Int,
    background: BackgroundColor
) -> [UInt8] {
    var mask = [UInt8](repeating: 0, count: width * height)
    var queue: [Int] = []

    func distance(_ pixel: Int) -> Double {
        let index = pixel * 4
        return colorDistance(
            red: Double(pixels[index]) / 255,
            green: Double(pixels[index + 1]) / 255,
            blue: Double(pixels[index + 2]) / 255,
            background: background
        )
    }

    func seed(_ pixel: Int) {
        guard mask[pixel] == 0,
              pixels[pixel * 4 + 3] < 8 || distance(pixel) <= background.strictTolerance
        else { return }
        mask[pixel] = 1
        queue.append(pixel)
    }

    for x in 0..<width {
        seed(x)
        if height > 1 { seed((height - 1) * width + x) }
    }
    if height > 2 {
        for y in 1..<(height - 1) {
            seed(y * width)
            if width > 1 { seed(y * width + width - 1) }
        }
    }

    var cursor = 0
    while cursor < queue.count {
        let pixel = queue[cursor]
        cursor += 1
        let x = pixel % width
        let y = pixel / width
        let neighbors = [
            x > 0 ? pixel - 1 : -1,
            x + 1 < width ? pixel + 1 : -1,
            y > 0 ? pixel - width : -1,
            y + 1 < height ? pixel + width : -1
        ]
        for neighbor in neighbors where neighbor >= 0 {
            guard mask[neighbor] == 0,
                  pixels[neighbor * 4 + 3] < 8
                    || distance(neighbor) <= background.strictTolerance
            else { continue }
            mask[neighbor] = 1
            queue.append(neighbor)
        }
    }

    var frontier = queue
    for layer in 2...4 {
        var next: [Int] = []
        for pixel in frontier {
            let x = pixel % width
            let y = pixel / width
            let neighbors = [
                x > 0 ? pixel - 1 : -1,
                x + 1 < width ? pixel + 1 : -1,
                y > 0 ? pixel - width : -1,
                y + 1 < height ? pixel + width : -1
            ]
            for neighbor in neighbors where neighbor >= 0 {
                guard mask[neighbor] == 0,
                      distance(neighbor) <= background.softTolerance
                else { continue }
                mask[neighbor] = UInt8(layer)
                next.append(neighbor)
            }
        }
        frontier = next
        if frontier.isEmpty { break }
    }
    return mask
}

private func encodePNG(_ image: CGImage, to url: URL) throws {
    let representation = NSBitmapImageRep(cgImage: image)
    guard let data = representation.representation(
        using: .png,
        properties: [.compressionFactor: 0.94]
    ) else {
        throw NSError(
            domain: "CainiaoPetArt",
            code: 5,
            userInfo: [NSLocalizedDescriptionKey: "Could not encode \(url.lastPathComponent)"]
        )
    }
    try data.write(to: url, options: .atomic)
}

private func valleyBoundary(
    near fraction: Double,
    width: Int,
    smoothedActivity: [Double]
) -> Int {
    let expected = Int(Double(width) * fraction)
    let radius = max(12, Int(Double(width) * 0.075))
    let lower = max(1, expected - radius)
    let upper = min(width - 2, expected + radius)
    return (lower...upper).min { left, right in
        let leftDistance = abs(left - expected)
        let rightDistance = abs(right - expected)
        let leftScore = smoothedActivity[left] + Double(leftDistance) * 0.002
        let rightScore = smoothedActivity[right] + Double(rightDistance) * 0.002
        return leftScore < rightScore
    } ?? expected
}

do {
    guard let image = NSImage(contentsOf: inputURL),
          let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else {
        throw NSError(
            domain: "CainiaoPetArt",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not decode \(inputURL.path)"]
        )
    }

    let width = source.width
    let height = source.height
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        throw NSError(
            domain: "CainiaoPetArt",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Could not create source context"]
        )
    }

    context.interpolationQuality = .high
    context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

    let background = inferredBorderBackground(pixels: pixels, width: width, height: height)
    let backgroundMask = connectedBackgroundMask(
        pixels: pixels,
        width: width,
        height: height,
        background: background
    )
    var columnActivity = [Double](repeating: 0, count: width)
    for y in 0..<height {
        for x in 0..<width {
            let index = y * bytesPerRow + x * 4
            let red = Double(pixels[index]) / 255
            let green = Double(pixels[index + 1]) / 255
            let blue = Double(pixels[index + 2]) / 255
            let originalAlpha = Double(pixels[index + 3]) / 255
            let isConnectedBackground = backgroundMask[y * width + x] != 0
            let distance = colorDistance(
                red: red,
                green: green,
                blue: blue,
                background: background
            )
            let alpha = isConnectedBackground
                ? smoothstep(background.strictTolerance * 0.48, background.softTolerance, distance)
                    * originalAlpha
                : originalAlpha

            if alpha < 0.012 {
                pixels[index] = 0
                pixels[index + 1] = 0
                pixels[index + 2] = 0
                pixels[index + 3] = 0
                continue
            }

            let fringe = isConnectedBackground ? (1 - alpha) * 0.92 : 0
            pixels[index] = UInt8(min(255, max(0, red - background.red * fringe) * alpha * 255))
            pixels[index + 1] = UInt8(min(255, max(0, green - background.green * fringe) * alpha * 255))
            pixels[index + 2] = UInt8(min(255, max(0, blue - background.blue * fringe) * alpha * 255))
            pixels[index + 3] = UInt8(min(255, alpha * 255))
            if alpha > 0.10 {
                columnActivity[x] += 1
            }
        }
    }

    let smoothingRadius = max(3, width / 320)
    var smoothedActivity = [Double](repeating: 0, count: width)
    for x in 0..<width {
        let lower = max(0, x - smoothingRadius)
        let upper = min(width - 1, x + smoothingRadius)
        smoothedActivity[x] = columnActivity[lower...upper].reduce(0, +) / Double(upper - lower + 1)
    }

    var componentLabels = [Int32](repeating: 0, count: width * height)
    var components: [PixelComponent] = []
    var pendingPixels: [Int] = []

    for y in 0..<height {
        for x in 0..<width {
            let pixelIndex = y * width + x
            guard componentLabels[pixelIndex] == 0,
                  pixels[y * bytesPerRow + x * 4 + 3] > 5
            else { continue }

            let label = Int32(components.count + 1)
            componentLabels[pixelIndex] = label
            pendingPixels.removeAll(keepingCapacity: true)
            pendingPixels.append(pixelIndex)
            var component = PixelComponent(
                label: label,
                area: 0,
                minimumX: x,
                maximumX: x,
                minimumY: y,
                maximumY: y,
                sumX: 0,
                sumY: 0,
                sumRed: 0,
                sumGreen: 0,
                sumBlue: 0
            )

            while let current = pendingPixels.popLast() {
                let currentX = current % width
                let currentY = current / width
                component.area += 1
                component.minimumX = min(component.minimumX, currentX)
                component.maximumX = max(component.maximumX, currentX)
                component.minimumY = min(component.minimumY, currentY)
                component.maximumY = max(component.maximumY, currentY)
                component.sumX += Int64(currentX)
                component.sumY += Int64(currentY)
                let colorIndex = currentY * bytesPerRow + currentX * 4
                component.sumRed += Int64(pixels[colorIndex])
                component.sumGreen += Int64(pixels[colorIndex + 1])
                component.sumBlue += Int64(pixels[colorIndex + 2])

                let lowerX = max(0, currentX - 1)
                let upperX = min(width - 1, currentX + 1)
                let lowerY = max(0, currentY - 1)
                let upperY = min(height - 1, currentY + 1)
                for neighborY in lowerY...upperY {
                    for neighborX in lowerX...upperX {
                        let neighbor = neighborY * width + neighborX
                        guard componentLabels[neighbor] == 0,
                              pixels[neighborY * bytesPerRow + neighborX * 4 + 3] > 5
                        else { continue }
                        componentLabels[neighbor] = label
                        pendingPixels.append(neighbor)
                    }
                }
            }

            components.append(component)
        }
    }

    let minimumSubjectSeparation = Double(width) * 0.105
    let usableComponents = components.filter { component in
        let componentWidth = component.maximumX - component.minimumX + 1
        let componentHeight = component.maximumY - component.minimumY + 1
        let isLayoutDivider = componentHeight > Int(Double(height) * 0.84)
            && componentWidth < Int(Double(width) * 0.035)
        return !component.isMagentaBackdropArtifact && !isLayoutDivider
    }
    var mainComponents: [PixelComponent] = []
    for component in usableComponents.sorted(by: { $0.area > $1.area }) {
        guard component.area >= 100,
              mainComponents.allSatisfy({
                  abs($0.centerX - component.centerX) >= minimumSubjectSeparation
              })
        else { continue }
        mainComponents.append(component)
        if mainComponents.count == stages.count { break }
    }
    mainComponents.sort { $0.centerX < $1.centerX }
    if mainComponents.count != stages.count {
        // Production prompts place one subject in each of five equal slots.
        // Highly segmented armor can prevent any one connected component from
        // representing a whole subject, so fall back to those explicit slots.
        mainComponents = stages.indices.map { index in
            let centerX = Int((Double(index) + 0.5) * Double(width) / Double(stages.count))
            return PixelComponent(
                label: Int32(-index - 1),
                area: 1,
                minimumX: centerX,
                maximumX: centerX,
                minimumY: height / 2,
                maximumY: height / 2,
                sumX: Int64(centerX),
                sumY: Int64(height / 2),
                sumRed: 0,
                sumGreen: 0,
                sumBlue: 0
            )
        }
        print("Primary component detection was segmented; using five equal production slots")
    }

    var boundaries = [0]
    for index in 0..<(mainComponents.count - 1) {
        boundaries.append(
            Int((mainComponents[index].centerX + mainComponents[index + 1].centerX) / 2)
        )
    }
    boundaries.append(width)

    var componentStage: [Int32: Int] = [:]
    for component in usableComponents where component.area >= 7 {
        let stageIndex = mainComponents.indices.min { left, right in
            abs(component.centerX - mainComponents[left].centerX)
                < abs(component.centerX - mainComponents[right].centerX)
        } ?? 0
        componentStage[component.label] = stageIndex
    }

    let componentSummary = components
        .filter { $0.area >= 100 }
        .sorted { $0.centerX < $1.centerX }
        .map { String(format: "%.0f:%d", $0.centerX, $0.area) }
        .joined(separator: ",")
    print("Candidate components: \(componentSummary)")
    let primaryCenters = mainComponents.map { String(format: "%.0f", $0.centerX) }
    print("Primary centers: \(primaryCenters.joined(separator: ","))")

    try FileManager.default.createDirectory(
        at: sourceDirectory,
        withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
        at: resourceDirectory,
        withIntermediateDirectories: true
    )

    for stageIndex in stages.indices {
        let stageComponents = components.filter {
            componentStage[$0.label] == stageIndex
        }
        var minimumX = width
        var maximumX = 0
        var minimumY = height
        var maximumY = 0

        for component in stageComponents {
            minimumX = min(minimumX, component.minimumX)
            maximumX = max(maximumX, component.maximumX)
            minimumY = min(minimumY, component.minimumY)
            maximumY = max(maximumY, component.maximumY)
        }

        guard minimumX <= maximumX, minimumY <= maximumY else {
            throw NSError(
                domain: "CainiaoPetArt",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "No subject found for \(theme)-\(stages[stageIndex])"]
            )
        }

        let subjectWidth = maximumX - minimumX + 1
        let subjectHeight = maximumY - minimumY + 1
        let xPadding = max(8, Int(Double(subjectWidth) * 0.06))
        let yPadding = max(8, Int(Double(subjectHeight) * 0.045))
        let cropX = max(0, minimumX - xPadding)
        let cropY = max(0, minimumY - yPadding)
        let cropMaxX = min(width - 1, maximumX + xPadding)
        let cropMaxY = min(height - 1, maximumY + yPadding)
        let cropWidth = cropMaxX - cropX + 1
        let cropHeight = cropMaxY - cropY + 1
        let cropBytesPerRow = cropWidth * 4
        var cropPixels = [UInt8](repeating: 0, count: cropHeight * cropBytesPerRow)

        for localY in 0..<cropHeight {
            let globalY = cropY + localY
            for localX in 0..<cropWidth {
                let globalX = cropX + localX
                let globalPixel = globalY * width + globalX
                guard componentStage[componentLabels[globalPixel]] == stageIndex else { continue }
                let sourceIndex = globalY * bytesPerRow + globalX * 4
                let destinationIndex = localY * cropBytesPerRow + localX * 4
                cropPixels[destinationIndex] = pixels[sourceIndex]
                cropPixels[destinationIndex + 1] = pixels[sourceIndex + 1]
                cropPixels[destinationIndex + 2] = pixels[sourceIndex + 2]
                cropPixels[destinationIndex + 3] = pixels[sourceIndex + 3]
            }
        }

        guard let cropContext = CGContext(
                data: &cropPixels,
                width: cropWidth,
                height: cropHeight,
                bitsPerComponent: 8,
                bytesPerRow: cropBytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
              ),
              let cropped = cropContext.makeImage(),
              let outputContext = CGContext(
                data: nil,
                width: outputSide,
                height: outputSide,
                bitsPerComponent: 8,
                bytesPerRow: outputSide * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
              )
        else {
            throw NSError(
                domain: "CainiaoPetArt",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "Could not crop \(theme)-\(stages[stageIndex])"]
            )
        }

        outputContext.clear(CGRect(x: 0, y: 0, width: outputSide, height: outputSide))
        outputContext.interpolationQuality = .high
        let inset: CGFloat = 50
        let available = CGFloat(outputSide) - inset * 2
        let scale = min(available / CGFloat(cropped.width), available / CGFloat(cropped.height))
        let targetWidth = CGFloat(cropped.width) * scale
        let targetHeight = CGFloat(cropped.height) * scale
        let targetRect = CGRect(
            x: (CGFloat(outputSide) - targetWidth) / 2,
            y: inset,
            width: targetWidth,
            height: targetHeight
        )
        outputContext.draw(cropped, in: targetRect)

        guard let outputImage = outputContext.makeImage() else {
            throw NSError(
                domain: "CainiaoPetArt",
                code: 7,
                userInfo: [NSLocalizedDescriptionKey: "Could not render \(theme)-\(stages[stageIndex])"]
            )
        }

        let sourceURL = sourceDirectory.appendingPathComponent("\(stages[stageIndex])-source.png")
        let resourceURL = resourceDirectory.appendingPathComponent("\(theme)-\(stages[stageIndex]).png")
        try encodePNG(outputImage, to: sourceURL)
        try encodePNG(outputImage, to: resourceURL)
        print("Prepared \(theme)-\(stages[stageIndex]).png")
    }

    print("Split boundaries: \(boundaries.map(String.init).joined(separator: ",")); components: \(components.count)")
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
