import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count >= 3,
      CommandLine.arguments.count.isMultiple(of: 2) == false
else {
    fputs("Usage: swift chroma-key-assets.swift input.png output.png [input output ...]\n", stderr)
    exit(2)
}

private func smoothstep(_ edge0: Double, _ edge1: Double, _ value: Double) -> Double {
    let t = min(1, max(0, (value - edge0) / (edge1 - edge0)))
    return t * t * (3 - 2 * t)
}

private func process(input: URL, output: URL) throws {
    guard let image = NSImage(contentsOf: input),
          let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else {
        throw NSError(domain: "SidekinArt", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Could not decode \(input.path)"
        ])
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
        throw NSError(domain: "SidekinArt", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "Could not create image context"
        ])
    }

    context.interpolationQuality = .high
    context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

    let keyR = 1.0
    let keyG = 0.0
    let keyB = 1.0

    for index in stride(from: 0, to: pixels.count, by: 4) {
        let red = Double(pixels[index]) / 255
        let green = Double(pixels[index + 1]) / 255
        let blue = Double(pixels[index + 2]) / 255

        let distance = max(
            abs(red - keyR),
            abs(green - keyG),
            abs(blue - keyB)
        )
        var alpha = smoothstep(0.105, 0.32, distance)
        let magentaDominance = max(0, min(red, blue) - green)
        let channelBalance = 1 - smoothstep(0.12, 0.24, abs(red - blue))
        let shadowKey = smoothstep(0.14, 0.31, magentaDominance) * channelBalance
        alpha *= 1 - shadowKey

        if alpha < 0.01 {
            pixels[index] = 0
            pixels[index + 1] = 0
            pixels[index + 2] = 0
            pixels[index + 3] = 0
            continue
        }

        // Suppress the narrow magenta fringe without changing opaque violet details.
        if alpha < 0.98 {
            let fringe = (1 - alpha) * 0.88
            let magentaExcess = max(0, min(red, blue) - green)
            let correctedRed = max(0, red - magentaExcess * fringe)
            let correctedBlue = max(0, blue - magentaExcess * fringe * 0.36)
            pixels[index] = UInt8(min(255, correctedRed * alpha * 255))
            pixels[index + 1] = UInt8(min(255, green * alpha * 255))
            pixels[index + 2] = UInt8(min(255, correctedBlue * alpha * 255))
        } else {
            pixels[index] = UInt8(min(255, red * alpha * 255))
            pixels[index + 1] = UInt8(min(255, green * alpha * 255))
            pixels[index + 2] = UInt8(min(255, blue * alpha * 255))
        }
        pixels[index + 3] = UInt8(min(255, alpha * 255))
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
        throw NSError(domain: "SidekinArt", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "Could not build output image"
        ])
    }

    let representation = NSBitmapImageRep(cgImage: cgImage)
    guard let png = representation.representation(using: .png, properties: [.compressionFactor: 0.92]) else {
        throw NSError(domain: "SidekinArt", code: 4, userInfo: [
            NSLocalizedDescriptionKey: "Could not encode output PNG"
        ])
    }

    try FileManager.default.createDirectory(
        at: output.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try png.write(to: output, options: .atomic)
}

do {
    var argumentIndex = 1
    while argumentIndex < CommandLine.arguments.count {
        let input = URL(fileURLWithPath: CommandLine.arguments[argumentIndex])
        let output = URL(fileURLWithPath: CommandLine.arguments[argumentIndex + 1])
        try process(input: input, output: output)
        print("Prepared \(output.lastPathComponent)")
        argumentIndex += 2
    }
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
