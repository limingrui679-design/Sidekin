import Foundation

guard CommandLine.arguments.count == 4 else {
    fputs("Usage: swift generate-theme-catalog.swift catalog-dir output.swift output.json\n", stderr)
    exit(2)
}

struct ThemeColor: Codable {
    let red: Double
    let green: Double
    let blue: Double
}

struct ThemeForm: Codable {
    let stage: String
    let name: String
    let introduction: String
    let visualAnchor: String
}

struct Theme: Codable {
    let id: String
    let displayName: String
    let category: String
    let subtitle: String
    let symbolName: String
    let lineageIntroduction: String
    let existenceAnchor: String
    let silhouetteAnchor: String
    let silhouetteClass: String
    let motionAnchor: String
    let locomotionClass: String
    let materialAnchor: String
    let energyAnchor: String
    let motionProfile: String
    let accent: ThemeColor
    let secondaryAccent: ThemeColor
    let forms: [ThemeForm]
}

struct Fragment: Codable {
    let themes: [Theme]
}

struct Envelope: Codable {
    let schemaVersion: Int
    let themes: [Theme]
}

enum CatalogError: Error, CustomStringConvertible {
    case invalid(String)

    var description: String {
        switch self {
        case let .invalid(message): message
        }
    }
}

let catalogDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let swiftOutput = URL(fileURLWithPath: CommandLine.arguments[2])
let jsonOutput = URL(fileURLWithPath: CommandLine.arguments[3])
let fileManager = FileManager.default
let categoryOrder = [
    "faunaMythic",
    "machinesVehicles",
    "floraFungi",
    "mineralGeological",
    "artifactsInstruments",
    "foodAlchemy",
    "elementalWeather",
    "cosmicAbstract",
    "livingArchitecture",
    "collectiveSystems"
]
let motionProfiles = Set([
    "buoyant", "mechanical", "agile", "poised", "swimming", "heavy", "bouncing",
    "prowling", "spectral", "rooted", "winged", "orbiting", "skittering", "serpentine",
    "pulsing", "gliding", "marching", "rolling", "swarming", "flowing"
])
let stages = ["egg", "hatchling", "juvenile", "ascended", "legendary"]

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw CatalogError.invalid(message) }
}

func unique(_ values: [String], label: String) throws {
    try require(Set(values).count == values.count, "Duplicate \(label) found in theme catalog")
}

func validateColor(_ color: ThemeColor, label: String) throws {
    for value in [color.red, color.green, color.blue] {
        try require((0...1).contains(value), "\(label) contains a color component outside 0...1")
    }
}

do {
    let files = try fileManager.contentsOfDirectory(
        at: catalogDirectory,
        includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension.lowercased() == "json" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
    try require(files.count == 10, "Expected 10 category fragments, found \(files.count)")

    var themes: [Theme] = []
    let decoder = JSONDecoder()
    for file in files {
        let fragment = try decoder.decode(Fragment.self, from: Data(contentsOf: file))
        try require(fragment.themes.count == 10, "\(file.lastPathComponent) must contain 10 themes")
        themes.append(contentsOf: fragment.themes)
    }

    try require(themes.count == 100, "Expected 100 complete themes, found \(themes.count)")
    try unique(themes.map(\.id), label: "theme ID")
    try unique(themes.map(\.displayName), label: "theme name")
    try unique(themes.map(\.lineageIntroduction), label: "lineage introduction")
    try unique(themes.map(\.existenceAnchor), label: "existence anchor")
    try unique(themes.map(\.silhouetteAnchor), label: "silhouette anchor")
    try unique(themes.map(\.motionAnchor), label: "motion anchor")
    try unique(themes.map(\.materialAnchor), label: "material anchor")
    try unique(themes.map(\.energyAnchor), label: "energy anchor")

    let categoryCounts = Dictionary(grouping: themes, by: \.category).mapValues(\.count)
    try require(Set(categoryCounts.keys) == Set(categoryOrder), "Catalog categories do not match the ten-category plan")
    for category in categoryOrder {
        try require(categoryCounts[category] == 10, "Category \(category) must contain exactly 10 themes")
    }

    let idCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
    for theme in themes {
        try require(!theme.id.isEmpty, "A theme has an empty ID")
        try require(theme.id.unicodeScalars.allSatisfy(idCharacters.contains), "Invalid theme ID: \(theme.id)")
        try require(theme.lineageIntroduction.count >= 55, "\(theme.id) has a short lineage introduction")
        try require(theme.existenceAnchor.count >= 5, "\(theme.id) has a short existence anchor")
        try require(theme.silhouetteAnchor.count >= 35, "\(theme.id) has a weak silhouette anchor")
        try require(theme.motionAnchor.count >= 25, "\(theme.id) has a weak motion anchor")
        try require(theme.materialAnchor.count >= 20, "\(theme.id) has a weak material anchor")
        try require(theme.energyAnchor.count >= 18, "\(theme.id) has a weak energy anchor")
        try require(motionProfiles.contains(theme.motionProfile), "\(theme.id) has unknown motion profile \(theme.motionProfile)")
        try validateColor(theme.accent, label: theme.id)
        try validateColor(theme.secondaryAccent, label: theme.id)
        try require(theme.forms.map(\.stage) == stages, "\(theme.id) must define the five canonical stages in order")
        for form in theme.forms {
            try require(form.name.count >= 5, "\(theme.id)/\(form.stage) has a short form name")
            try require(form.introduction.count >= 42, "\(theme.id)/\(form.stage) has a short introduction")
            try require(form.visualAnchor.count >= 28, "\(theme.id)/\(form.stage) has a weak visual anchor")
        }
    }

    try require(Set(themes.map(\.silhouetteClass)).count >= 18, "Catalog needs at least 18 silhouette classes")
    try require(Set(themes.map(\.locomotionClass)).count >= 18, "Catalog needs at least 18 locomotion classes")

    let forms = themes.flatMap(\.forms)
    try require(forms.count == 500, "Expected 500 described forms, found \(forms.count)")
    try unique(forms.map(\.name), label: "form name")
    try unique(forms.map(\.introduction), label: "form introduction")
    try unique(forms.map(\.visualAnchor), label: "stage visual anchor")

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(Envelope(schemaVersion: 1, themes: themes))
    guard let json = String(data: data, encoding: .utf8) else {
        throw CatalogError.invalid("Could not encode the catalog as UTF-8")
    }

    let swiftSource = [
        "// Generated by Scripts/generate-theme-catalog.swift. Do not edit by hand.",
        "import Foundation",
        "",
        "enum PetThemeCatalogGenerated {",
        "    static let json = #\"\"\"",
        json,
        "\"\"\"#",
        "}",
        ""
    ].joined(separator: "\n")

    try fileManager.createDirectory(at: swiftOutput.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: jsonOutput.deletingLastPathComponent(), withIntermediateDirectories: true)
    try swiftSource.write(to: swiftOutput, atomically: true, encoding: .utf8)
    try data.write(to: jsonOutput, options: .atomic)
    print("Generated 100 themes and 500 described forms.")
} catch {
    fputs("Theme catalog generation failed: \(error)\n", stderr)
    exit(1)
}
