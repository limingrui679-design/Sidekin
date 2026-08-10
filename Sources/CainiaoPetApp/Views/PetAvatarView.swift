import AppKit
import CainiaoPetCore
import ImageIO
import SwiftUI

struct PetAvatarView: View {
    let stage: PetStage
    let theme: PetVisualTheme
    let customAssetURL: URL?
    let activity: CodexActivity
    let isSleeping: Bool
    var size: CGFloat = 220
    var isAnimated = true

    var body: some View {
        Group {
            if isAnimated {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
                    avatarFrame(time: context.date.timeIntervalSinceReferenceDate)
                }
            } else {
                avatarFrame(time: 0)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pet, \(stage.displayName), \(activity.displayName)")
    }

    private func avatarFrame(time: TimeInterval) -> some View {
        PetAvatarFrame(
            stage: stage,
            theme: theme,
            customAssetURL: customAssetURL,
            activity: activity,
            isSleeping: isSleeping,
            usesThumbnail: !isAnimated,
            time: time
        )
    }
}

private struct PetAvatarFrame: View {
    let stage: PetStage
    let theme: PetVisualTheme
    let customAssetURL: URL?
    let activity: CodexActivity
    let isSleeping: Bool
    let usesThumbnail: Bool
    let time: TimeInterval

    var body: some View {
        GeometryReader { proxy in
            let movement = motion
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [stage.accent(for: theme).opacity(0.28), .black.opacity(0.22), .clear],
                            center: .center,
                            startRadius: 2,
                            endRadius: width * 0.32
                        )
                    )
                    .frame(width: width * 0.62, height: height * 0.12)
                    .blur(radius: width * 0.012)
                    .position(x: width * 0.5, y: height * 0.87)

                ZStack {
                    CharacterRender(
                        stage: stage,
                        theme: theme,
                        customAssetURL: customAssetURL,
                        activity: activity,
                        isSleeping: isSleeping,
                        usesThumbnail: usesThumbnail
                    )
                    ActivityFXLayer(
                        activity: activity,
                        isSleeping: isSleeping,
                        accent: stage.accent(for: theme),
                        time: time
                    )
                }
                .offset(x: movement.x, y: movement.y)
                .rotationEffect(.degrees(movement.rotation))
                .scaleEffect(x: movement.scaleX, y: movement.scaleY, anchor: .bottom)
            }
            .frame(width: width, height: height)
            .compositingGroup()
        }
    }

    private var motion: (
        x: CGFloat,
        y: CGFloat,
        rotation: Double,
        scaleX: CGFloat,
        scaleY: CGFloat
    ) {
        if isSleeping {
            let breath = CGFloat(sin(time * 1.55))
            return (0, 4 + breath, 0, 1.0 - breath * 0.006, 0.985 + breath * 0.012)
        }

        switch activity {
        case .idle:
            let drift = CGFloat(sin(time * 1.8))
            switch theme {
            case .nova:
                return (drift * 0.8, drift * 2.8, sin(time * 0.9) * 0.8, 1, 1)
            case .mecha:
                let thrum = CGFloat(sin(time * 4.2))
                return (0, -abs(thrum) * 0.8, thrum.doubleValue * 0.18, 1.002, 0.998)
            case .street:
                return (drift * 3.0, -abs(drift) * 1.2, drift.doubleValue * 2.1, 1.01, 0.995)
            case .samurai:
                return (0, drift * 0.75, drift.doubleValue * 0.28, 1, 1 + drift * 0.004)
            case .abyss:
                return (CGFloat(sin(time * 0.92)) * 3.2, CGFloat(cos(time * 1.25)) * 3.6, sin(time * 0.78) * 1.5, 1, 1)
            case .volcanic:
                return (0, abs(drift) * 0.55, drift.doubleValue * 0.18, 1.004, 0.998)
            case .candy:
                let bounce = CGFloat(abs(sin(time * 2.25)))
                return (drift * 1.2, -bounce * 5.5, drift.doubleValue * 1.3, 1.02 - bounce * 0.018, 0.98 + bounce * 0.026)
            case .wasteland:
                return (drift * 1.9, -abs(drift) * 1.5, drift.doubleValue * 1.25, 1, 1)
            case .phantom:
                return (CGFloat(sin(time * 0.75)) * 2.6, CGFloat(cos(time * 1.05)) * 4.2, sin(time * 0.58) * 1.1, 1, 1.008)
            case .totem:
                return (0, abs(drift) * 0.7, drift.doubleValue * 0.34, 1.003, 0.999)
            }
        case .running:
            let pulse = CGFloat(sin(time * 7.2))
            switch theme {
            case .street, .abyss, .phantom:
                return (pulse * 4.2, -abs(pulse) * 3.0, pulse.doubleValue * 2.5, 1.022, 0.985)
            case .candy:
                let bounce = CGFloat(abs(sin(time * 6.0)))
                return (pulse * 2.0, -bounce * 8.0, pulse.doubleValue * 2.2, 1.035 - bounce * 0.025, 0.97 + bounce * 0.04)
            default:
                return (pulse * 1.2, -abs(pulse) * 3.2, pulse.doubleValue * 0.8, 1.016, 0.988)
            }
        case .completed:
            let pulse = CGFloat(abs(sin(time * 4.6)))
            return (0, -pulse * 3.5, 0, 1.015 + pulse * 0.025, 1.015 + pulse * 0.025)
        case .failed:
            let shake = CGFloat(sin(time * 31))
            return (shake * 3.2, 3, shake.doubleValue * 0.75, 0.99, 0.985)
        }
    }
}

private struct CharacterRender: View {
    let stage: PetStage
    let theme: PetVisualTheme
    let customAssetURL: URL?
    let activity: CodexActivity
    let isSleeping: Bool
    let usesThumbnail: Bool

    var body: some View {
        Image(
            nsImage: PetCharacterAssets.image(
                named: stage.assetName(for: theme),
                customURL: customAssetURL,
                thumbnail: usesThumbnail
            )
        )
        .resizable()
        .interpolation(.high)
        .antialiased(true)
        .scaledToFit()
        .scaleEffect(customAssetURL == nil ? stage.renderScale : 1)
        .saturation(isSleeping ? 0.70 : activity == .failed ? 0.82 : 1)
        .brightness(isSleeping ? -0.06 : activity == .completed ? 0.035 : 0)
        .shadow(
            color: stage.accent(for: theme).opacity(isSleeping ? 0.18 : 0.42),
            radius: 10,
            y: 5
        )
        .shadow(color: .black.opacity(0.36), radius: 6, y: 6)
    }
}

@MainActor
private enum PetCharacterAssets {
    private static let bundleName = "CainiaoPet_CainiaoPetApp.bundle"

    private static let resourceBundle: Bundle? = {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent(bundleName),
            Bundle.main.bundleURL.appendingPathComponent(bundleName)
        ]
        return candidates.compactMap { $0 }.compactMap(Bundle.init(url:)).first
    }()

    private static let imageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 80
        cache.totalCostLimit = 192 * 1_024 * 1_024
        return cache
    }()

    static func image(named name: String, customURL: URL?, thumbnail: Bool) -> NSImage {
        let sourceKey = customURL?.path ?? "bundle:\(name)"
        let key = "\(sourceKey)|\(thumbnail ? "thumb" : "full")" as NSString
        if let cached = imageCache.object(forKey: key) { return cached }

        let url = customURL ?? resourceBundle?.url(forResource: name, withExtension: "png")
        guard let url else { return NSImage(size: NSSize(width: 1, height: 1)) }

        let image: NSImage
        let cost: Int
        if thumbnail,
           let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let cgImage = CGImageSourceCreateThumbnailAtIndex(
               source,
               0,
               [
                   kCGImageSourceCreateThumbnailFromImageAlways: true,
                   kCGImageSourceCreateThumbnailWithTransform: true,
                   kCGImageSourceShouldCacheImmediately: true,
                   kCGImageSourceThumbnailMaxPixelSize: 360
               ] as CFDictionary
           ) {
            image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            cost = cgImage.width * cgImage.height * 4
        } else if let fullImage = NSImage(contentsOf: url) {
            image = fullImage
            cost = 1_254 * 1_254 * 4
        } else {
            return NSImage(size: NSSize(width: 1, height: 1))
        }

        imageCache.setObject(image, forKey: key, cost: cost)
        return image
    }
}

private struct ActivityFXLayer: View {
    let activity: CodexActivity
    let isSleeping: Bool
    let accent: Color
    let time: TimeInterval

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            if isSleeping {
                VStack(alignment: .leading, spacing: -4) {
                    Text("Z")
                    Text("Z")
                        .font(.system(size: width * 0.055, weight: .black, design: .rounded))
                        .offset(x: 15)
                }
                .font(.system(size: width * 0.09, weight: .black, design: .rounded))
                .foregroundStyle(accent)
                .shadow(color: .indigo, radius: 5)
                .position(x: width * 0.80, y: height * 0.22)
                .offset(y: -CGFloat((time * 6).truncatingRemainder(dividingBy: 10)))
            } else {
                switch activity {
                case .idle:
                    EmptyView()
                case .running:
                    ZStack {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [.clear, accent.opacity(0.9), .white, accent.opacity(0.9), .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: width * 0.58, height: 1.5)
                            .shadow(color: accent, radius: 4)
                            .position(
                                x: width * 0.5,
                                y: height * (0.26 + 0.48 * CGFloat((time * 0.55).truncatingRemainder(dividingBy: 1)))
                            )
                        StatusBadge(color: accent, symbol: "chevron.forward.2")
                            .frame(width: width * 0.18, height: width * 0.14)
                            .position(x: width * 0.82, y: height * 0.21)
                    }
                case .completed:
                    StatusBadge(color: .green, symbol: "checkmark")
                        .frame(width: width * 0.17, height: width * 0.17)
                        .scaleEffect(0.94 + CGFloat(abs(sin(time * 4))) * 0.08)
                        .position(x: width * 0.81, y: height * 0.22)
                case .failed:
                    StatusBadge(color: .orange, symbol: "exclamationmark")
                        .frame(width: width * 0.17, height: width * 0.17)
                        .position(x: width * 0.81, y: height * 0.22)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct StatusBadge: View {
    let color: Color
    let symbol: String

    var body: some View {
        ZStack {
            CutCornerShape(cut: 8)
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.98), color.opacity(0.56), Color.black.opacity(0.88)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(CutCornerShape(cut: 8).stroke(Color.white.opacity(0.82), lineWidth: 1.5))
                .shadow(color: color, radius: 10)
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(.white)
        }
    }
}

private struct CutCornerShape: Shape {
    let cut: CGFloat

    func path(in rect: CGRect) -> Path {
        let amount = min(cut, min(rect.width, rect.height) * 0.34)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + amount, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - amount, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + amount))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - amount))
        path.addLine(to: CGPoint(x: rect.maxX - amount, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + amount, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - amount))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + amount))
        path.closeSubpath()
        return path
    }
}

private extension CGFloat {
    var doubleValue: Double { Double(self) }
}

private extension PetStage {
    func assetName(for theme: PetVisualTheme) -> String {
        "\(theme.rawValue)-\(rawValue)"
    }

    func accent(for theme: PetVisualTheme) -> Color {
        switch theme {
        case .nova:
            switch self {
            case .egg, .hatchling: return .cyan
            case .juvenile: return .blue
            case .ascended: return .indigo
            case .legendary: return .purple
            }
        default:
            return isEvolved ? theme.secondaryAccentColor : theme.accentColor
        }
    }

    var renderScale: CGFloat {
        switch self {
        case .egg: 0.88
        case .hatchling: 0.94
        case .juvenile: 1.0
        case .ascended: 1.03
        case .legendary: 1.02
        }
    }
}
