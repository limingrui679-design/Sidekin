import Foundation

struct CatalogEnvelope: Decodable {
    struct Theme: Decodable {
        let displayName: String
    }

    let themes: [Theme]
}

enum AuditError: LocalizedError {
    case failure(String)

    var errorDescription: String? {
        switch self {
        case let .failure(message): message
        }
    }
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw AuditError.failure(message) }
}

let projectRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let fileManager = FileManager.default
let catalogURL = projectRoot.appendingPathComponent("ArtSources/PET_THEME_CATALOG.json")
let auditURL = projectRoot.appendingPathComponent("docs/LINEAGE_AUDIT.md")
let replacementsURL = projectRoot.appendingPathComponent("ArtSources/AuditReplacements")
let sheetsURL = projectRoot.appendingPathComponent("ArtSources/AuditSheets")

do {
    let catalog = try JSONDecoder().decode(
        CatalogEnvelope.self,
        from: Data(contentsOf: catalogURL)
    )
    try require(catalog.themes.count == 100, "Catalog must contain exactly 100 themes.")

    let audit = try String(contentsOf: auditURL, encoding: .utf8)
    let expression = try NSRegularExpression(
        pattern: #"(?m)^\| ([0-9]{3}) \| ([^|]+) \| (Pass(?: after repair)?) \|"#
    )
    let range = NSRange(audit.startIndex..<audit.endIndex, in: audit)
    let rows = expression.matches(in: audit, range: range).map { match -> (Int, String, String) in
        let index = Int((audit as NSString).substring(with: match.range(at: 1))) ?? -1
        let name = (audit as NSString).substring(with: match.range(at: 2))
            .trimmingCharacters(in: .whitespaces)
        let result = (audit as NSString).substring(with: match.range(at: 3))
        return (index, name, result)
    }
    try require(rows.count == 100, "Lineage audit must contain exactly 100 result rows.")

    for (offset, row) in rows.enumerated() {
        let expectedIndex = offset + 1
        try require(row.0 == expectedIndex, "Audit row numbering drifted at row \(expectedIndex).")
        try require(
            row.1 == catalog.themes[offset].displayName,
            "Audit row \(expectedIndex) does not match catalog theme \(catalog.themes[offset].displayName)."
        )
    }

    let repairedRows = rows.filter { $0.2 == "Pass after repair" }.count
    try require(repairedRows == 61, "Expected 61 repaired lineage rows, found \(repairedRows).")

    let replacementChildren = try fileManager.contentsOfDirectory(
        at: replacementsURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    )
    let replacementDirectories = try replacementChildren.filter { url in
        try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
    }
    try require(
        replacementDirectories.count == repairedRows,
        "Replacement directory count does not match repaired lineage count."
    )

    let replacementFiles = try fileManager.subpathsOfDirectory(atPath: replacementsURL.path)
        .filter { $0.range(of: #"audit-raw(?:-v[0-9]+)?\.png$"#, options: .regularExpression) != nil }
    try require(replacementFiles.count == 77, "Expected 77 raw repair candidates, found \(replacementFiles.count).")

    let uniqueTargets = Set(replacementFiles.map { path in
        path.replacingOccurrences(
            of: #"-audit-raw(?:-v[0-9]+)?\.png$"#,
            with: "",
            options: .regularExpression
        )
    })
    try require(uniqueTargets.count == 74, "Expected 74 unique repair targets, found \(uniqueTargets.count).")

    let expectedSheets = Set((1...20).map { String(format: "lineage-audit-%02d.png", $0) })
    let actualSheets = Set(try fileManager.contentsOfDirectory(atPath: sheetsURL.path))
    try require(actualSheets == expectedSheets, "Final lineage audit sheet set is incomplete or contains drift.")

    print(
        "Verified 100 individual lineage audit rows, 61 repaired lineages, "
            + "77 raw candidates, 74 repair targets, and 20 final sheets."
    )
} catch {
    fputs("Lineage audit verification failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
