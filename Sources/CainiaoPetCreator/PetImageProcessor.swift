import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum PetImageProcessorError: LocalizedError {
    case cannotDecode
    case cannotCreateContext
    case emptySubject
    case cannotEncode

    public var errorDescription: String? {
        switch self {
        case .cannotDecode: "无法读取所选图片。"
        case .cannotCreateContext: "无法创建图片处理画布。"
        case .emptySubject: "没有从生成结果中识别到宠物主体，请换一条描述后重试。"
        case .cannotEncode: "无法保存处理后的宠物图片。"
        }
    }
}

public enum PetImageProcessor {
    public static func normalizeReference(_ data: Data, side: Int = 1_024) throws -> Data {
        guard let source = decodeCGImage(data, maxPixelSize: max(2_048, side * 2)) else {
            throw PetImageProcessorError.cannotDecode
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw PetImageProcessorError.cannotCreateContext
        }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let margin = CGFloat(side) * 0.035
        let available = CGFloat(side) - margin * 2
        let scale = min(available / CGFloat(source.width), available / CGFloat(source.height))
        let width = CGFloat(source.width) * scale
        let height = CGFloat(source.height) * scale
        context.interpolationQuality = .high
        context.draw(
            source,
            in: CGRect(
                x: (CGFloat(side) - width) / 2,
                y: (CGFloat(side) - height) / 2,
                width: width,
                height: height
            )
        )
        guard let output = context.makeImage() else {
            throw PetImageProcessorError.cannotCreateContext
        }
        return try encodePNG(output)
    }

    public static func prepareGeneratedAsset(
        _ data: Data,
        outputSide: Int = 1_254
    ) throws -> Data {
        guard let source = decodeCGImage(data, maxPixelSize: max(2_048, outputSide * 2)) else {
            throw PetImageProcessorError.cannotDecode
        }

        let width = source.width
        let height = source.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let sourceContext = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw PetImageProcessorError.cannotCreateContext
        }
        sourceContext.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

        let background = inferredBorderBackground(pixels: pixels, width: width, height: height)
        let backgroundMask = connectedBackgroundMask(
            pixels: pixels,
            width: width,
            height: height,
            background: background
        )
        var minimumX = width
        var maximumX = -1
        var minimumY = height
        var maximumY = -1

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

                // Only defringe pixels belonging to the edge-connected matte.
                // Pink or purple pixels enclosed by the subject remain fully
                // opaque and retain their original color.
                let fringe = isConnectedBackground ? (1 - alpha) * 0.92 : 0
                let correctedRed = max(0, red - background.red * fringe)
                let correctedGreen = max(0, green - background.green * fringe)
                let correctedBlue = max(0, blue - background.blue * fringe)
                pixels[index] = UInt8(min(255, correctedRed * alpha * 255))
                pixels[index + 1] = UInt8(min(255, correctedGreen * alpha * 255))
                pixels[index + 2] = UInt8(min(255, correctedBlue * alpha * 255))
                pixels[index + 3] = UInt8(min(255, alpha * 255))

                if alpha > 0.08 {
                    minimumX = min(minimumX, x)
                    maximumX = max(maximumX, x)
                    minimumY = min(minimumY, y)
                    maximumY = max(maximumY, y)
                }
            }
        }

        guard maximumX >= minimumX, maximumY >= minimumY,
              let keyedImage = sourceContext.makeImage() else {
            throw PetImageProcessorError.emptySubject
        }

        let paddingX = max(4, Int(Double(maximumX - minimumX + 1) * 0.035))
        let paddingY = max(4, Int(Double(maximumY - minimumY + 1) * 0.035))
        let crop = CGRect(
            x: max(0, minimumX - paddingX),
            y: max(0, minimumY - paddingY),
            width: min(width - max(0, minimumX - paddingX), maximumX - minimumX + 1 + paddingX * 2),
            height: min(height - max(0, minimumY - paddingY), maximumY - minimumY + 1 + paddingY * 2)
        )
        guard let subject = keyedImage.cropping(to: crop) else {
            throw PetImageProcessorError.emptySubject
        }

        guard let outputContext = CGContext(
            data: nil,
            width: outputSide,
            height: outputSide,
            bitsPerComponent: 8,
            bytesPerRow: outputSide * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw PetImageProcessorError.cannotCreateContext
        }
        outputContext.clear(CGRect(x: 0, y: 0, width: outputSide, height: outputSide))
        let maximumSubjectSide = CGFloat(outputSide) * 0.84
        let scale = min(
            maximumSubjectSide / CGFloat(subject.width),
            maximumSubjectSide / CGFloat(subject.height)
        )
        let targetWidth = CGFloat(subject.width) * scale
        let targetHeight = CGFloat(subject.height) * scale
        let targetRect = CGRect(
            x: (CGFloat(outputSide) - targetWidth) / 2,
            y: (CGFloat(outputSide) - targetHeight) / 2 + CGFloat(outputSide) * 0.015,
            width: targetWidth,
            height: targetHeight
        )
        outputContext.interpolationQuality = .high
        outputContext.draw(subject, in: targetRect)
        guard let output = outputContext.makeImage() else {
            throw PetImageProcessorError.cannotCreateContext
        }
        return try encodePNG(output)
    }

    private struct BackgroundColor {
        var red: Double
        var green: Double
        var blue: Double
        var strictTolerance: Double
        var softTolerance: Double
    }

    private static func inferredBorderBackground(
        pixels: [UInt8],
        width: Int,
        height: Int
    ) -> BackgroundColor {
        let bucketCount = 8 * 8 * 8
        var counts = [Int](repeating: 0, count: bucketCount)
        var redSums = [Double](repeating: 0, count: bucketCount)
        var greenSums = [Double](repeating: 0, count: bucketCount)
        var blueSums = [Double](repeating: 0, count: bucketCount)
        var samples: [(red: Double, green: Double, blue: Double, bucket: Int)] = []
        samples.reserveCapacity((width + height) * 2)

        func addSample(x: Int, y: Int) {
            let index = (y * width + x) * 4
            guard pixels[index + 3] > 127 else { return }
            let red = Double(pixels[index]) / 255
            let green = Double(pixels[index + 1]) / 255
            let blue = Double(pixels[index + 2]) / 255
            let redBucket = min(7, Int(red * 8))
            let greenBucket = min(7, Int(green * 8))
            let blueBucket = min(7, Int(blue * 8))
            let bucket = redBucket * 64 + greenBucket * 8 + blueBucket
            counts[bucket] += 1
            redSums[bucket] += red
            greenSums[bucket] += green
            blueSums[bucket] += blue
            samples.append((red, green, blue, bucket))
        }

        for x in 0..<width {
            addSample(x: x, y: 0)
            if height > 1 { addSample(x: x, y: height - 1) }
        }
        if height > 2 {
            for y in 1..<(height - 1) {
                addSample(x: 0, y: y)
                if width > 1 { addSample(x: width - 1, y: y) }
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
            .filter { $0.bucket == dominant }
            .map {
                pow($0.red - red, 2) + pow($0.green - green, 2) + pow($0.blue - blue, 2)
            }
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

    private static func connectedBackgroundMask(
        pixels: [UInt8],
        width: Int,
        height: Int,
        background: BackgroundColor
    ) -> [UInt8] {
        let count = width * height
        var mask = [UInt8](repeating: 0, count: count)
        var queue: [Int] = []
        queue.reserveCapacity(max(width * 2 + height * 2, count / 4))

        func distance(at pixelIndex: Int) -> Double {
            let byteIndex = pixelIndex * 4
            return colorDistance(
                red: Double(pixels[byteIndex]) / 255,
                green: Double(pixels[byteIndex + 1]) / 255,
                blue: Double(pixels[byteIndex + 2]) / 255,
                background: background
            )
        }

        func seed(_ pixelIndex: Int) {
            guard mask[pixelIndex] == 0,
                  pixels[pixelIndex * 4 + 3] < 8
                    || distance(at: pixelIndex) <= background.strictTolerance
            else { return }
            mask[pixelIndex] = 1
            queue.append(pixelIndex)
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
                        || distance(at: neighbor) <= background.strictTolerance
                else { continue }
                mask[neighbor] = 1
                queue.append(neighbor)
            }
        }

        // Grow only a few pixels beyond the strictly connected core. This
        // captures anti-aliased color-key fringes without flood-filling a pink
        // or purple subject whose color happens to resemble the background.
        var frontier = queue
        for layer in 2...4 {
            var next: [Int] = []
            next.reserveCapacity(frontier.count / 2)
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
                          distance(at: neighbor) <= background.softTolerance
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

    private static func colorDistance(
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

    private static func smoothstep(_ edge0: Double, _ edge1: Double, _ value: Double) -> Double {
        let amount = min(1, max(0, (value - edge0) / (edge1 - edge0)))
        return amount * amount * (3 - 2 * amount)
    }

    private static func decodeCGImage(_ data: Data, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary)
    }

    private static func encodePNG(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw PetImageProcessorError.cannotEncode
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw PetImageProcessorError.cannotEncode
        }
        return data as Data
    }
}
