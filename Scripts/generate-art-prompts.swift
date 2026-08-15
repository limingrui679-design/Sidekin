import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: swift generate-art-prompts.swift catalog.json output-directory\n", stderr)
    exit(2)
}

struct Color: Decodable {
    let red: Double
    let green: Double
    let blue: Double
}

struct Form: Decodable {
    let stage: String
    let name: String
    let introduction: String
    let visualAnchor: String
}

struct Theme: Decodable {
    let id: String
    let displayName: String
    let category: String?
    let tags: [String]?
    let artStyle: String?
    let subtitle: String
    let lineageIntroduction: String
    let existenceAnchor: String
    let silhouetteAnchor: String
    let silhouetteClass: String
    let motionAnchor: String
    let locomotionClass: String
    let materialAnchor: String
    let energyAnchor: String
    let accent: Color
    let secondaryAccent: Color
    let forms: [Form]
}

struct Envelope: Decodable {
    let themes: [Theme]
}

let catalogURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let fileManager = FileManager.default
let catalog = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: catalogURL))

func distance(_ color: Color, to candidate: (Double, Double, Double)) -> Double {
    let red = color.red - candidate.0
    let green = color.green - candidate.1
    let blue = color.blue - candidate.2
    return sqrt(red * red + green * green + blue * blue)
}

func chromaKey(for theme: Theme) -> String {
    let candidates: [(hex: String, rgb: (Double, Double, Double))] = [
        ("#00FF00", (0, 1, 0)),
        ("#FF00FF", (1, 0, 1)),
        ("#FFFF00", (1, 1, 0))
    ]
    return candidates.max { left, right in
        let leftDistance = min(
            distance(theme.accent, to: left.rgb),
            distance(theme.secondaryAccent, to: left.rgb)
        )
        let rightDistance = min(
            distance(theme.accent, to: right.rgb),
            distance(theme.secondaryAccent, to: right.rgb)
        )
        return leftDistance < rightDistance
    }!.hex
}

func categoryName(_ rawValue: String) -> String {
    [
        "faunaMythic": "Fauna & Mythic",
        "machinesVehicles": "Machines & Vehicles",
        "floraFungi": "Flora & Fungi",
        "mineralGeological": "Mineral & Geological",
        "artifactsInstruments": "Artifacts & Instruments",
        "foodAlchemy": "Food & Alchemy",
        "elementalWeather": "Elemental & Weather",
        "cosmicAbstract": "Cosmic & Abstract",
        "livingArchitecture": "Living Architecture",
        "collectiveSystems": "Collective Systems"
    ][rawValue] ?? rawValue
}

func taxonomyName(for theme: Theme) -> String {
    if let category = theme.category { return categoryName(category) }
    return (theme.tags ?? []).joined(separator: " · ")
}

let stageRules = [
    "Stage I is a compact origin container, seed, core, field, diagram, module, or incomplete organism. Do not expose the complete mature limb set. Make the origin readable and specific rather than a generic egg.",
    "Stage II reveals the defining existence type, persistent identity feature, and basic locomotion. Use juvenile proportions and a clearly smaller, simpler construction than the mature forms.",
    "Stage III establishes the signature topology, locomotion, functional tool or organ, and material system. Change the outer contour and pose from Stage II without losing identity.",
    "Stage IV is a structural ascension: change stance, functional anatomy, formation, or architecture. Preserve the same face, core, facade, or identity marker; do not merely add armor.",
    "Stage V is the unmistakable crown form. Make a major outline, scale, formation, or system change while preserving the same lineage, identity marker, and existence type."
]

for theme in catalog.themes {
    guard theme.forms.count == 5 else {
        throw NSError(domain: "ArtPromptGenerator", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "\(theme.id) does not contain five forms"
        ])
    }
    let themeDirectory = outputDirectory.appendingPathComponent(theme.id, isDirectory: true)
    try fileManager.createDirectory(at: themeDirectory, withIntermediateDirectories: true)
    let key = chromaKey(for: theme)

    for (index, form) in theme.forms.enumerated() {
        let continuity: String
        if index == 0 {
            continuity = """
            This is the first stage and has no reference image. Establish a persistent identity marker that later stages can retain: use the catalog's core, face, facade, aperture, emblem, or focal feature. Do not depict the mature body early.
            """
        } else {
            let previous = theme.forms[index - 1]
            continuity = """
            The provided reference image is the immediately preceding form, \(previous.name). Evolve exactly that same individual and lineage. Preserve its recognizable face or primary core/facade, signature palette, defining material, and persistent focal marker. The new silhouette must be structurally different, but it must never switch species, existence type, number/topology logic, or unrelated design language. Previous-stage anchor: \(previous.visualAnchor)
            """
        }

        let prompt = """
        Create exactly one complete full-body subject for a premium competitive-game macOS floating pet.

        Theme: \(theme.displayName) [\(taxonomyName(for: theme))]
        Art-style direction: \(theme.artStyle ?? "catalog-defined premium competitive-game companion")
        Form: \(form.name), canonical \(form.stage) stage
        Lineage concept: \(theme.lineageIntroduction)
        Existence anchor: \(theme.existenceAnchor)
        Persistent silhouette logic: \(theme.silhouetteAnchor)
        Silhouette topology class: \(theme.silhouetteClass)
        Movement and locomotion: \(theme.motionAnchor); \(theme.locomotionClass)
        Material system: \(theme.materialAnchor)
        Energy motif: \(theme.energyAnchor)
        Current-stage introduction: \(form.introduction)
        Current-stage visual anchor: \(form.visualAnchor)

        \(continuity)

        Progression rule: \(stageRules[index])

        Art direction: polished high-end 3D competitive-game character render, original collectible arena companion, deliberately readable silhouette, clear focal feature, production-quality anatomy or construction, crisp material separation, controlled specular highlights, rich but disciplined color, and strong small-size readability. Do not imitate any existing franchise. Non-animal themes must stay genuinely non-animal; never add a generic face, fox ears, horns, dragon anatomy, four animal legs, or humanoid armor unless this theme explicitly requires them. Any explicitly humanoid subject must still read as a clearly nonhuman creature, deity, spirit, construct, food being, machine, or abstract lifeform—never depict a real human, human child, realistic human skin, realistic human hair, or an ordinary human face.

        Composition: exactly one subject, centered on a square canvas, complete and uncropped, every limb/module/ribbon/ring/architectural component fully visible, generous padding, no floor and no detached unrelated props. Use a three-quarter presentation unless the visual anchor explicitly calls for profile, radial, top-down, diagrammatic, or architectural framing.

        Background: perfectly flat solid \(key), edge to edge. No floor, cast shadow, contact shadow, gradient, fog, texture, vignette, reflection, or lighting variation on the background. The exact key color \(key) must not appear anywhere on the subject.

        Hard exclusions: no scenery, frame, border, typography, letters, numbers, logo, watermark, duplicate subject, cropped component, generic upright humanoid substitution, recolor-only evolution, species drift, existence-type drift, or unrelated costume redesign.
        """

        let outputURL = themeDirectory.appendingPathComponent("\(form.stage).txt")
        try prompt.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}

print("Generated \(catalog.themes.count * 5) stage prompts for \(catalog.themes.count) complete themes.")
