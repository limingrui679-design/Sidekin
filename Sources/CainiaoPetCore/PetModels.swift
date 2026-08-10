import Foundation

public enum PetStage: String, Codable, CaseIterable, Identifiable, Sendable {
    case egg
    case hatchling
    case juvenile
    case ascended
    case legendary

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .egg: "Stage I · Core Egg"
        case .hatchling: "Stage II · First Spark"
        case .juvenile: "Stage III · Shifting Form"
        case .ascended: "Stage IV · Ascension"
        case .legendary: "Stage V · Crown Form"
        }
    }

    public var shortName: String {
        switch self {
        case .egg: "Core Egg"
        case .hatchling: "First Spark"
        case .juvenile: "Shifting Form"
        case .ascended: "Ascension"
        case .legendary: "Crown Form"
        }
    }

    public var subtitle: String {
        switch self {
        case .egg: "The species anchors are taking shape inside the shell"
        case .hatchling: "Its juvenile silhouette and movement style emerge"
        case .juvenile: "Signature limbs, tools, and energy organs begin to mature"
        case .ascended: "Its combat stance and abilities undergo a structural leap"
        case .legendary: "The lineage reaches its unmistakable apex"
        }
    }

    public var isEvolved: Bool {
        rank >= PetStage.ascended.rank
    }

    public var isFinal: Bool {
        self == .legendary
    }

    public var rank: Int {
        switch self {
        case .egg: 0
        case .hatchling: 1
        case .juvenile: 2
        case .ascended: 3
        case .legendary: 4
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        // Four-stage saves used guardian/dreamer as two terminal branches. Both
        // migrate to the fourth stage so an existing pet never loses progress.
        if value == "guardian" || value == "dreamer" {
            self = .ascended
            return
        }

        guard let stage = Self(rawValue: value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown pet stage: \(value)"
            )
        }
        self = stage
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum CodexActivity: String, Codable, CaseIterable, Identifiable, Sendable {
    case idle
    case running
    case completed
    case failed

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .idle: "Resting"
        case .running: "Codex is working"
        case .completed: "Task complete"
        case .failed: "Task needs attention"
        }
    }
}

public enum PetCareAction: String, Codable, Sendable {
    case feed
    case play
    case sleepOrWake
}

public enum PetVisualTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case nova
    case mecha
    case street
    case samurai
    case abyss
    case volcanic
    case candy
    case wasteland
    case phantom
    case totem

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .nova: "Nova Arena"
        case .mecha: "Vanguard Mecha"
        case .street: "Street Brawl"
        case .samurai: "Sakura Blade"
        case .abyss: "Abyssal Tidehunter"
        case .volcanic: "Molten Tyrant"
        case .candy: "Candy Carnival"
        case .wasteland: "Wasteland Salvager"
        case .phantom: "Phantom Veil"
        case .totem: "Verdant Totem"
        }
    }

    public var subtitle: String {
        switch self {
        case .nova: "Crystal energy · astral arena"
        case .mecha: "Ceramic armor · alert-orange core"
        case .street: "Graffiti armor · acid neon"
        case .samurai: "Vermilion warplate · sakura energy"
        case .abyss: "Deep-sea carapace · tidal bioluminescence"
        case .volcanic: "Obsidian layers · molten fissures"
        case .candy: "Candy toys · gummy energy"
        case .wasteland: "Scrap-built armor · corroded brass"
        case .phantom: "Shadow plate · spectral green ectoplasm"
        case .totem: "Carved wood and stone · amber tree energy"
        }
    }

    public var symbolName: String {
        switch self {
        case .nova: "sparkles"
        case .mecha: "cpu.fill"
        case .street: "bolt.fill"
        case .samurai: "fan.fill"
        case .abyss: "water.waves"
        case .volcanic: "flame.fill"
        case .candy: "heart.fill"
        case .wasteland: "wrench.and.screwdriver.fill"
        case .phantom: "moon.stars.fill"
        case .totem: "leaf.fill"
        }
    }

    public var speciesAnchor: String {
        switch self {
        case .nova: "Astral Crystal Moonhare"
        case .mecha: "Wheel-Paw Mecha Mastiff"
        case .street: "Graffiti Gecko"
        case .samurai: "Red Fox × Crane"
        case .abyss: "Salamander × Crab × Manta"
        case .volcanic: "Pangolin × Ankylosaur"
        case .candy: "Balloon Hare × Gummy Spirit"
        case .wasteland: "Armored Fennec"
        case .phantom: "Moth-Cat Wraith"
        case .totem: "Ancient Tree Stag × Boar"
        }
    }

    public var silhouetteAnchor: String {
        switch self {
        case .nova: "Crescent ears, comet-tail streamers, and a crystal starbow"
        case .mecha: "Low broad shoulders, wheel-paws, and a deployable turret spine"
        case .street: "Long suction limbs, a spray-can tail, and skateboard side rails"
        case .samurai: "Crane-legged profile, fan-feather tail, and crescent wing blades"
        case .abyss: "Wide horizontal body, many fins and limbs, and giant ring-shaped manta wings"
        case .volcanic: "Ground-hugging arched back, layered rock plate, and a massive hammer tail"
        case .candy: "Rounded springy body, ribbon-like ears, and a halo of balloon rings"
        case .wasteland: "Huge-eared quadruped with cargo modules, crane rig, and radio array"
        case .phantom: "Footless smoke tail, cloak-like moth wings, and an eclipse disc"
        case .totem: "Four root-hooves, boar-like shoulders, and worldtree crown antlers"
        }
    }

    public var motionAnchor: String {
        switch self {
        case .nova: "Weightless leaps and suspended bow draws"
        case .mecha: "Grounded four-paw siege charges"
        case .street: "Crouched slides and one-handed freezes"
        case .samurai: "Profile draw-cuts and one-legged crane stances"
        case .abyss: "Horizontal drifting swims"
        case .volcanic: "Coiled power-up followed by a low headlong impact"
        case .candy: "Bounces, hovering, and aerial flips"
        case .wasteland: "Four-paw sidesteps and load-bearing sprints"
        case .phantom: "Inverted hovering and sideways spellcasting"
        case .totem: "Steady four-hoof stomps that summon roots"
        }
    }

    public var materialAnchor: String {
        switch self {
        case .nova: "Translucent star crystal and flexible deep-blue armor"
        case .mecha: "White ceramic panels and gunmetal joints"
        case .street: "Worn rubber, stickers, and spray-painted polymer"
        case .samurai: "Vermilion lacquer, black iron, washi, and pale-gold knots"
        case .abyss: "Pearlescent shell, wet skin, and transparent fins"
        case .volcanic: "Obsidian, basalt horns, and molten cracks"
        case .candy: "Transparent gummy, wrappers, frosting, and jelly"
        case .wasteland: "Rusty copper, old canvas, improvised steel, and exposed cable"
        case .phantom: "Velvet shadow, smoke, and moon-silver foil"
        case .totem: "Carved wood, mossy stone, and resin amber"
        }
    }

    public var energyAnchor: String {
        switch self {
        case .nova: "Four-point star core and gravity orbits"
        case .mecha: "Orange hexagonal reactor"
        case .street: "Acid-green soundwaves and red graffiti bursts"
        case .samurai: "A petal crescent gathering along the blade"
        case .abyss: "Cyan bioluminescence and pressure rings"
        case .volcanic: "Orange-white underfire and erupting crown ridges"
        case .candy: "Rainbow bubbles and a heart-shaped candy core"
        case .wasteland: "Amber reclaimed battery and sandstorm arcs"
        case .phantom: "Spectral green maskfire and an eclipse disc"
        case .totem: "Amber heartwood and luminous growth rings"
        }
    }

    public func formName(at stage: PetStage) -> String {
        let names: [String]
        switch self {
        case .nova:
            names = ["Starshuttle Crystal Egg", "Moonleap Leveret", "Astral Crystal Scout", "Starbow Ranger", "Skybound Pathfinder"]
        case .mecha:
            names = ["Folding Hex Pod", "Twin-Wheel Scout", "Wheel-Paw Mecha Mastiff", "Deployed Fortress Hound", "Celestial Mobile Bastion"]
        case .street:
            names = ["Rattlecan Egg", "Grounded Gecko", "Skateboard Tagger", "Sonic Brawler", "City-Roar Gecko"]
        case .samurai:
            names = ["Folding-Fan Egg", "Sheath-Tail Kit", "Sakura Blade Cadet", "Crane-Step Swordmaster", "Thousand-Petal Winglord"]
        case .abyss:
            names = ["Tidebubble Spawn", "Six-Fin Driftling", "Pincerwing Tidehunter", "Abyssal Tide Rider", "Great-Ring Sovereign Ray"]
        case .volcanic:
            names = ["Faceted Magma Core", "Cinderclaw Whelp", "Coil-Armor Pangolin", "Hammer-Tail Siegebeast", "Magma-Crowned Ley Dragon"]
        case .candy:
            names = ["Twisted Wrapper Cocoon", "Bouncing Gummy Hare", "Toffee Acrobat", "Carnival Illusionist", "Star-Candy Dreamsmith"]
        case .wasteland:
            names = ["Rust-Can Incubator", "Scrap-Picker Kit", "Load-Bearing Scout", "Crane-Rig Mechanic", "Radio-Colossus Fennec"]
        case .phantom:
            names = ["Moonmark Lantern Cocoon", "Inverted Mistwing", "Shadowveil Moth-Cat", "Eclipse Arcanist", "Faceless Nightveil"]
        case .totem:
            names = ["Cracked Amber Seed", "Root-Hoof Fawn", "Mossplate Calf", "Grove-Rune Hornbeast", "Worldtree Crownstag"]
        }
        return names[stage.rank]
    }
}

public enum PetTemplateGenerationMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case text
    case restyle
    case faithful

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .text: "Text Original"
        case .restyle: "Reference Restyle"
        case .faithful: "High-Fidelity Reference"
        }
    }

    public var requiresReferenceImage: Bool {
        self != .text
    }
}

public enum PetImageGenerationQuality: String, Codable, CaseIterable, Identifiable, Sendable {
    case low
    case medium
    case high

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .low: "Draft"
        case .medium: "Standard"
        case .high: "Final"
        }
    }

    public var detail: String {
        switch self {
        case .low: "Fastest; best for checking the silhouette"
        case .medium: "Balanced detail and cost"
        case .high: "Maximum detail at the highest cost"
        }
    }

    /// Published GPT Image 2 output-only estimate for a 1024×1024 image.
    /// Text and reference-image input tokens are intentionally excluded because
    /// their cost depends on the concrete request.
    public var estimatedOutputUSDPerSquareImage: Double {
        switch self {
        case .low: 0.006
        case .medium: 0.053
        case .high: 0.211
        }
    }

    public func estimatedOutputUSD(stageCount: Int) -> Double {
        estimatedOutputUSDPerSquareImage * Double(max(0, stageCount))
    }
}

public struct CustomPetStageDefinition: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var index: Int
    public var name: String
    public var prompt: String
    public var experienceThreshold: Int
    public var assetFileName: String

    public init(
        id: String = UUID().uuidString,
        index: Int,
        name: String,
        prompt: String = "",
        experienceThreshold: Int,
        assetFileName: String
    ) {
        self.id = id
        self.index = index
        self.name = name
        self.prompt = prompt
        self.experienceThreshold = experienceThreshold
        self.assetFileName = assetFileName
    }
}

public struct CustomPetTemplate: Codable, Equatable, Identifiable, Sendable {
    public var schemaVersion: Int
    public var id: String
    public var name: String
    public var basePrompt: String
    public var artDirection: String
    public var generationMode: PetTemplateGenerationMode
    /// Optional so templates created by v1.1 remain decodable.
    public var generationQuality: PetImageGenerationQuality?
    public var referenceFileName: String?
    public var createdAt: Date
    public var fallbackTheme: PetVisualTheme
    public var stages: [CustomPetStageDefinition]

    public init(
        schemaVersion: Int = 1,
        id: String = UUID().uuidString,
        name: String,
        basePrompt: String,
        artDirection: String,
        generationMode: PetTemplateGenerationMode,
        generationQuality: PetImageGenerationQuality? = nil,
        referenceFileName: String? = nil,
        createdAt: Date = Date(),
        fallbackTheme: PetVisualTheme = .nova,
        stages: [CustomPetStageDefinition]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.basePrompt = basePrompt
        self.artDirection = artDirection
        self.generationMode = generationMode
        self.generationQuality = generationQuality
        self.referenceFileName = referenceFileName
        self.createdAt = createdAt
        self.fallbackTheme = fallbackTheme
        self.stages = stages.sorted { $0.index < $1.index }
    }

    public func stageIndex(for experience: Int) -> Int {
        let ordered = stages.sorted { $0.experienceThreshold < $1.experienceThreshold }
        guard !ordered.isEmpty else { return 0 }
        return ordered.lastIndex { experience >= $0.experienceThreshold } ?? 0
    }

    public var resolvedGenerationQuality: PetImageGenerationQuality {
        generationQuality ?? .medium
    }
}

public enum CustomGrowthStagePlan {
    public static let minimumStageCount = 1
    public static let maximumStageCount = 8

    private static let canonicalThresholds = [0, 20, 75, 180, 360]
    private static let canonicalNames = ["Core Egg", "First Spark", "Shifting Form", "Ascension", "Crown Form"]
    private static let extendedNames = ["Origin", "Hatchling", "Sprout", "Shifting Form", "Mature", "Ascension", "Transcendent", "Crown Form"]

    public static func clampedCount(_ count: Int) -> Int {
        min(maximumStageCount, max(minimumStageCount, count))
    }

    public static func defaultNames(count: Int) -> [String] {
        let count = clampedCount(count)
        if count == canonicalNames.count { return canonicalNames }
        if count == 1 { return ["Complete Form"] }
        if count == extendedNames.count { return extendedNames }

        return (0..<count).map { index in
            let position = Double(index) / Double(count - 1)
            let extendedIndex = Int((position * Double(extendedNames.count - 1)).rounded())
            return extendedNames[extendedIndex]
        }
    }

    public static func thresholds(count: Int) -> [Int] {
        let count = clampedCount(count)
        if count == 1 { return [0] }
        if count == canonicalThresholds.count { return canonicalThresholds }

        return (0..<count).map { index in
            let normalized = Double(index) / Double(count - 1)
            let position = normalized * Double(canonicalThresholds.count - 1)
            let lower = min(canonicalThresholds.count - 1, Int(floor(position)))
            let upper = min(canonicalThresholds.count - 1, lower + 1)
            let fraction = position - Double(lower)
            let value = Double(canonicalThresholds[lower])
                + Double(canonicalThresholds[upper] - canonicalThresholds[lower]) * fraction
            return Int(value.rounded())
        }
    }

    public static func canonicalStage(customIndex: Int, stageCount: Int) -> PetStage {
        let count = clampedCount(stageCount)
        guard count > 1 else { return .legendary }
        let clampedIndex = min(count - 1, max(0, customIndex))
        let rank = Int((Double(clampedIndex) / Double(count - 1) * 4).rounded())
        return PetStage.allCases[min(4, max(0, rank))]
    }
}

public struct PetTemplateSelection: Codable, Equatable, Sendable {
    /// `theme` keeps old skin saves decodable; decorations are intentionally ignored.
    public var theme: PetVisualTheme?
    public var customTemplateID: String?

    public init(
        theme: PetVisualTheme? = .nova,
        customTemplateID: String? = nil
    ) {
        self.theme = theme
        self.customTemplateID = customTemplateID
    }

    public var resolvedTheme: PetVisualTheme {
        theme ?? .nova
    }
}

public struct PetStats: Codable, Equatable, Sendable {
    public var hunger: Double
    public var mood: Double
    public var energy: Double

    public init(hunger: Double = 76, mood: Double = 82, energy: Double = 78) {
        self.hunger = hunger
        self.mood = mood
        self.energy = energy
        clamp()
    }

    public mutating func clamp() {
        hunger = min(100, max(0, hunger))
        mood = min(100, max(0, mood))
        energy = min(100, max(0, energy))
    }
}

public struct PetSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var name: String
    public var createdAt: Date
    public var lastUpdatedAt: Date
    public var activityChangedAt: Date
    public var stats: PetStats
    public var experience: Int
    public var stage: PetStage
    public var isSleeping: Bool
    public var codexActivity: CodexActivity
    /// The JSON key remains `wardrobe` so existing local saves migrate without loss.
    public var wardrobe: PetTemplateSelection
    public var careAffinity: Int
    public var sparkAffinity: Int
    public var feedCount: Int
    public var playCount: Int
    public var restCount: Int
    public var completedTasks: Int
    public var failedTasks: Int
    public var processedCodexSignals: [String]?
    public var lastCodexSignalAt: Date?
    public var lastCodexSignalActivity: CodexActivity?

    public init(name: String = "Sprout", now: Date = Date()) {
        self.schemaVersion = 3
        self.name = name
        self.createdAt = now
        self.lastUpdatedAt = now
        self.activityChangedAt = now
        self.stats = PetStats()
        self.experience = 0
        self.stage = .egg
        self.isSleeping = false
        self.codexActivity = .idle
        self.wardrobe = PetTemplateSelection()
        self.careAffinity = 0
        self.sparkAffinity = 0
        self.feedCount = 0
        self.playCount = 0
        self.restCount = 0
        self.completedTasks = 0
        self.failedTasks = 0
        self.processedCodexSignals = []
        self.lastCodexSignalAt = nil
        self.lastCodexSignalActivity = nil
    }

    public var wellbeing: Double {
        (stats.hunger + stats.mood + stats.energy) / 3
    }

    public var nextStageThreshold: Int? {
        switch stage {
        case .egg: 20
        case .hatchling: 75
        case .juvenile: 180
        case .ascended: 360
        case .legendary: nil
        }
    }

    public var stageProgress: Double {
        switch stage {
        case .egg:
            min(1, Double(experience) / 20)
        case .hatchling:
            min(1, max(0, Double(experience - 20) / 55))
        case .juvenile:
            min(1, max(0, Double(experience - 75) / 105))
        case .ascended:
            min(1, max(0, Double(experience - 180) / 180))
        case .legendary:
            1
        }
    }
}
