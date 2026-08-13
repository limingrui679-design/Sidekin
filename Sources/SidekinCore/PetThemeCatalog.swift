import Foundation

// Sidekin's built-in lineage catalog remains data-driven and locally bundled.

public enum PetThemeCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case faunaMythic
    case machinesVehicles
    case floraFungi
    case mineralGeological
    case artifactsInstruments
    case foodAlchemy
    case elementalWeather
    case cosmicAbstract
    case livingArchitecture
    case collectiveSystems

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .faunaMythic: "Fauna & Mythic"
        case .machinesVehicles: "Machines & Vehicles"
        case .floraFungi: "Flora & Fungi"
        case .mineralGeological: "Mineral & Geological"
        case .artifactsInstruments: "Artifacts & Instruments"
        case .foodAlchemy: "Food & Alchemy"
        case .elementalWeather: "Elemental & Weather"
        case .cosmicAbstract: "Cosmic & Abstract"
        case .livingArchitecture: "Living Architecture"
        case .collectiveSystems: "Collective Systems"
        }
    }

    public var symbolName: String {
        switch self {
        case .faunaMythic: "pawprint.fill"
        case .machinesVehicles: "gearshape.2.fill"
        case .floraFungi: "leaf.fill"
        case .mineralGeological: "mountain.2.fill"
        case .artifactsInstruments: "wand.and.stars"
        case .foodAlchemy: "flask.fill"
        case .elementalWeather: "cloud.bolt.rain.fill"
        case .cosmicAbstract: "sparkles"
        case .livingArchitecture: "building.2.fill"
        case .collectiveSystems: "circle.grid.cross.fill"
        }
    }
}

public enum PetMotionProfile: String, Codable, CaseIterable, Sendable {
    case buoyant
    case mechanical
    case agile
    case poised
    case swimming
    case heavy
    case bouncing
    case prowling
    case spectral
    case rooted
    case winged
    case orbiting
    case skittering
    case serpentine
    case pulsing
    case gliding
    case marching
    case rolling
    case swarming
    case flowing
}

public struct PetThemeColor: Codable, Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

public struct PetThemeFormProfile: Codable, Equatable, Sendable {
    public let stage: PetStage
    public let name: String
    public let introduction: String
    public let visualAnchor: String

    public init(stage: PetStage, name: String, introduction: String, visualAnchor: String) {
        self.stage = stage
        self.name = name
        self.introduction = introduction
        self.visualAnchor = visualAnchor
    }
}

public struct PetThemeProfile: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let category: PetThemeCategory
    public let subtitle: String
    public let symbolName: String
    public let lineageIntroduction: String
    public let existenceAnchor: String
    public let silhouetteAnchor: String
    public let silhouetteClass: String
    public let motionAnchor: String
    public let locomotionClass: String
    public let materialAnchor: String
    public let energyAnchor: String
    public let motionProfile: PetMotionProfile
    public let accent: PetThemeColor
    public let secondaryAccent: PetThemeColor
    public let forms: [PetThemeFormProfile]
}

private struct PetThemeCatalogEnvelope: Codable {
    let schemaVersion: Int
    let themes: [PetThemeProfile]
}

private enum PetThemeCatalogStore {
    static let profiles: [PetThemeProfile] = {
        do {
            let data = Data(PetThemeCatalogGenerated.json.utf8)
            let envelope = try JSONDecoder().decode(PetThemeCatalogEnvelope.self, from: data)
            precondition(envelope.schemaVersion == 1, "Unsupported built-in theme catalog schema")
            precondition(envelope.themes.count == 100, "Built-in theme catalog must contain 100 themes")
            precondition(Set(envelope.themes.map(\.id)).count == envelope.themes.count, "Duplicate theme IDs")
            return envelope.themes
        } catch {
            preconditionFailure("The built-in theme catalog is invalid: \(error)")
        }
    }()

    static let profileByID: [String: PetThemeProfile] = {
        Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
    }()
}

public struct PetVisualTheme: RawRepresentable, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    public let rawValue: String

    private init(uncheckedRawValue: String) {
        rawValue = uncheckedRawValue
    }

    public init?(rawValue: String) {
        guard PetThemeCatalogStore.profileByID[rawValue] != nil else { return nil }
        self.init(uncheckedRawValue: rawValue)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let theme = Self(rawValue: value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown pet theme: \(value)"
            )
        }
        self = theme
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var id: String { rawValue }

    public static let allCases: [PetVisualTheme] = PetThemeCatalogStore.profiles.map {
        PetVisualTheme(uncheckedRawValue: $0.id)
    }

    public static let nova = PetVisualTheme(uncheckedRawValue: "nova")
    public static let mecha = PetVisualTheme(uncheckedRawValue: "mecha")
    public static let street = PetVisualTheme(uncheckedRawValue: "street")
    public static let samurai = PetVisualTheme(uncheckedRawValue: "samurai")
    public static let abyss = PetVisualTheme(uncheckedRawValue: "abyss")
    public static let volcanic = PetVisualTheme(uncheckedRawValue: "volcanic")
    public static let candy = PetVisualTheme(uncheckedRawValue: "candy")
    public static let wasteland = PetVisualTheme(uncheckedRawValue: "wasteland")
    public static let phantom = PetVisualTheme(uncheckedRawValue: "phantom")
    public static let totem = PetVisualTheme(uncheckedRawValue: "totem")
    public static let tempest = PetVisualTheme(uncheckedRawValue: "tempest")
    public static let chrono = PetVisualTheme(uncheckedRawValue: "chrono")

    public var profile: PetThemeProfile {
        guard let profile = PetThemeCatalogStore.profileByID[rawValue] else {
            preconditionFailure("Missing profile for built-in theme \(rawValue)")
        }
        return profile
    }

    public var displayName: String { profile.displayName }
    public var category: PetThemeCategory { profile.category }
    public var subtitle: String { profile.subtitle }
    public var symbolName: String { profile.symbolName }
    public var lineageIntroduction: String { profile.lineageIntroduction }
    public var speciesAnchor: String { profile.existenceAnchor }
    public var existenceAnchor: String { profile.existenceAnchor }
    public var silhouetteAnchor: String { profile.silhouetteAnchor }
    public var silhouetteClass: String { profile.silhouetteClass }
    public var motionAnchor: String { profile.motionAnchor }
    public var locomotionClass: String { profile.locomotionClass }
    public var materialAnchor: String { profile.materialAnchor }
    public var energyAnchor: String { profile.energyAnchor }
    public var motionProfile: PetMotionProfile { profile.motionProfile }
    public var accentRGB: PetThemeColor { profile.accent }
    public var secondaryAccentRGB: PetThemeColor { profile.secondaryAccent }

    public func formName(at stage: PetStage) -> String {
        formProfile(at: stage).name
    }

    public func formIntroduction(at stage: PetStage) -> String {
        formProfile(at: stage).introduction
    }

    public func formVisualAnchor(at stage: PetStage) -> String {
        formProfile(at: stage).visualAnchor
    }

    private func formProfile(at stage: PetStage) -> PetThemeFormProfile {
        guard let form = profile.forms.first(where: { $0.stage == stage }) else {
            preconditionFailure("Theme \(rawValue) is missing stage \(stage.rawValue)")
        }
        return form
    }
}
