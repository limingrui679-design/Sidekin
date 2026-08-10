import CainiaoPetCore
import SwiftUI

extension PetVisualTheme {
    var accentColor: Color {
        switch self {
        case .nova: .cyan
        case .mecha: .orange
        case .street: Color(red: 0.70, green: 1.00, blue: 0.05)
        case .samurai: Color(red: 1.00, green: 0.24, blue: 0.48)
        case .abyss: Color(red: 0.00, green: 0.84, blue: 0.72)
        case .volcanic: Color(red: 1.00, green: 0.24, blue: 0.05)
        case .candy: Color(red: 1.00, green: 0.36, blue: 0.72)
        case .wasteland: Color(red: 0.92, green: 0.58, blue: 0.12)
        case .phantom: Color(red: 0.88, green: 0.18, blue: 1.00)
        case .totem: Color(red: 0.58, green: 0.76, blue: 0.18)
        }
    }

    var secondaryAccentColor: Color {
        switch self {
        case .nova: .purple
        case .mecha: .cyan
        case .street: Color(red: 1.00, green: 0.20, blue: 0.25)
        case .samurai: Color(red: 1.00, green: 0.72, blue: 0.15)
        case .abyss: Color(red: 0.10, green: 0.42, blue: 0.92)
        case .volcanic: Color(red: 1.00, green: 0.72, blue: 0.05)
        case .candy: Color(red: 0.25, green: 0.95, blue: 0.84)
        case .wasteland: Color(red: 0.76, green: 0.30, blue: 0.08)
        case .phantom: Color(red: 0.25, green: 1.00, blue: 0.75)
        case .totem: Color(red: 1.00, green: 0.55, blue: 0.06)
        }
    }

    var glowColors: [Color] {
        [accentColor, .white, secondaryAccentColor]
    }

    var previewBackground: LinearGradient {
        LinearGradient(
            colors: [accentColor.opacity(0.20), secondaryAccentColor.opacity(0.10), .black.opacity(0.08)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
