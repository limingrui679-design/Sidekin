import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count >= 3,
      CommandLine.arguments.count.isMultiple(of: 2) == false
else {
    fputs(
        "Usage: swift clean-enclosed-chroma-pockets.swift input.png output.png [input output ...]\n",
        stderr
    )
    exit(2)
}

private struct PixelColor {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
}

private func process(input: URL, output: URL) throws {
    guard let image = NSImage(contentsOf: input),
          let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else {
        throw NSError(
            domain: "SidekinArt",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not decode \(input.path)"]
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
            domain: "SidekinArt",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Could not create image context"]
        )
    }

    context.interpolationQuality = .none
    context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

    func color(at pixelIndex: Int) -> PixelColor {
        let byteIndex = pixelIndex * 4
        let alpha = Double(pixels[byteIndex + 3]) / 255
        guard alpha > 0.001 else {
            return PixelColor(red: 0, green: 0, blue: 0, alpha: 0)
        }
        return PixelColor(
            red: min(1, Double(pixels[byteIndex]) / 255 / alpha),
            green: min(1, Double(pixels[byteIndex + 1]) / 255 / alpha),
            blue: min(1, Double(pixels[byteIndex + 2]) / 255 / alpha),
            alpha: alpha
        )
    }

    func keyDistance(_ color: PixelColor) -> Double {
        max(abs(color.red - 1), color.green, abs(color.blue - 1))
    }

    func isStrictKey(_ pixelIndex: Int) -> Bool {
        let value = color(at: pixelIndex)
        return value.alpha > 0.08 && keyDistance(value) <= 0.13
    }

    func isLooseFringe(_ pixelIndex: Int) -> Bool {
        let value = color(at: pixelIndex)
        let balance = abs(value.red - value.blue)
        let dominance = min(value.red, value.blue) - value.green
        return value.alpha > 0.04
            && keyDistance(value) <= 0.32
            && balance <= 0.20
            && dominance >= 0.38
    }

    let pixelCount = width * height
    var visited = [Bool](repeating: false, count: pixelCount)
    var removeMask = [Bool](repeating: false, count: pixelCount)
    var removedComponents = 0
    var removedSeeds = 0

    for start in 0 ..< pixelCount where !visited[start] && isStrictKey(start) {
        var queue = [start]
        var cursor = 0
        var component: [Int] = []
        visited[start] = true

        while cursor < queue.count {
            let current = queue[cursor]
            cursor += 1
            component.append(current)
            let x = current % width
            let y = current / width

            if x > 0 {
                let neighbor = current - 1
                if !visited[neighbor] && isStrictKey(neighbor) {
                    visited[neighbor] = true
                    queue.append(neighbor)
                }
            }
            if x + 1 < width {
                let neighbor = current + 1
                if !visited[neighbor] && isStrictKey(neighbor) {
                    visited[neighbor] = true
                    queue.append(neighbor)
                }
            }
            if y > 0 {
                let neighbor = current - width
                if !visited[neighbor] && isStrictKey(neighbor) {
                    visited[neighbor] = true
                    queue.append(neighbor)
                }
            }
            if y + 1 < height {
                let neighbor = current + width
                if !visited[neighbor] && isStrictKey(neighbor) {
                    visited[neighbor] = true
                    queue.append(neighbor)
                }
            }
        }

        // Generated chroma backgrounds form broad, nearly uniform islands. Tiny
        // pink highlights are intentionally left untouched.
        guard component.count >= 100 else { continue }
        removedComponents += 1
        removedSeeds += component.count
        for index in component { removeMask[index] = true }
    }

    // Include only a narrow anti-aliased fringe around confirmed flat islands.
    for _ in 0 ..< 6 {
        var additions: [Int] = []
        for index in 0 ..< pixelCount where removeMask[index] {
            let x = index % width
            let y = index / width
            if x > 0 {
                let neighbor = index - 1
                if !removeMask[neighbor] && isLooseFringe(neighbor) { additions.append(neighbor) }
            }
            if x + 1 < width {
                let neighbor = index + 1
                if !removeMask[neighbor] && isLooseFringe(neighbor) { additions.append(neighbor) }
            }
            if y > 0 {
                let neighbor = index - width
                if !removeMask[neighbor] && isLooseFringe(neighbor) { additions.append(neighbor) }
            }
            if y + 1 < height {
                let neighbor = index + width
                if !removeMask[neighbor] && isLooseFringe(neighbor) { additions.append(neighbor) }
            }
        }
        if additions.isEmpty { break }
        for index in additions { removeMask[index] = true }
    }

    let removedPixels = removeMask.reduce(into: 0) { count, remove in
        if remove { count += 1 }
    }
    for pixelIndex in 0 ..< pixelCount where removeMask[pixelIndex] {
        let byteIndex = pixelIndex * 4
        pixels[byteIndex] = 0
        pixels[byteIndex + 1] = 0
        pixels[byteIndex + 2] = 0
        pixels[byteIndex + 3] = 0
    }

    guard let outputContext = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ), let cgImage = outputContext.makeImage()
    else {
        throw NSError(
            domain: "SidekinArt",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Could not build output image"]
        )
    }

    let representation = NSBitmapImageRep(cgImage: cgImage)
    guard let png = representation.representation(using: .png, properties: [.compressionFactor: 0.92]) else {
        throw NSError(
            domain: "SidekinArt",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "Could not encode output PNG"]
        )
    }

    try FileManager.default.createDirectory(
        at: output.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try png.write(to: output, options: .atomic)
    print(
        "Cleaned \(output.lastPathComponent): "
            + "\(removedComponents) flat pocket(s), \(removedSeeds) seed pixels, "
            + "\(removedPixels) pixels including fringe"
    )
}

do {
    var argumentIndex = 1
    while argumentIndex < CommandLine.arguments.count {
        let input = URL(fileURLWithPath: CommandLine.arguments[argumentIndex])
        let output = URL(fileURLWithPath: CommandLine.arguments[argumentIndex + 1])
        try process(input: input, output: output)
        argumentIndex += 2
    }
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
