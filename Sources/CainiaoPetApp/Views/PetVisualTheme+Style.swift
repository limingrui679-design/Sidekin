import CainiaoPetCore
import SwiftUI

extension PetVisualTheme {
    var accentColor: Color {
        Color(
            red: accentRGB.red,
            green: accentRGB.green,
            blue: accentRGB.blue
        )
    }

    var secondaryAccentColor: Color {
        Color(
            red: secondaryAccentRGB.red,
            green: secondaryAccentRGB.green,
            blue: secondaryAccentRGB.blue
        )
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
