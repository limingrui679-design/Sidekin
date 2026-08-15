import Foundation

struct CatalogEnvelope: Decodable {
    struct Theme: Decodable {
        let displayName: String
    }

    let themes: [Theme]
}

struct ExpansionProgress: Decodable {
    let generatedLineups: [String]
    let processedLineages: [String]
    let reviewedLineages: [String]
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
let expansionAuditURL = projectRoot.appendingPathComponent("docs/EXPANSION_AUDIT.md")
let replacementsURL = projectRoot.appendingPathComponent("ArtSources/AuditReplacements")
let sheetsURL = projectRoot.appendingPathComponent("ArtSources/AuditSheets")
let expansionRoot = projectRoot.appendingPathComponent("ArtSources/Expansion200", isDirectory: true)

func auditRows(in audit: String) throws -> [(Int, String, String)] {
    let expression = try NSRegularExpression(
        pattern: #"(?m)^\| ([0-9]{3}) \| ([^|]+) \| (Pass(?: after (?:repair|continuity repair|progression repair))?) \|"#
    )
    let range = NSRange(audit.startIndex..<audit.endIndex, in: audit)
    return expression.matches(in: audit, range: range).map { match -> (Int, String, String) in
        let index = Int((audit as NSString).substring(with: match.range(at: 1))) ?? -1
        let name = (audit as NSString).substring(with: match.range(at: 2))
            .trimmingCharacters(in: .whitespaces)
        let result = (audit as NSString).substring(with: match.range(at: 3))
        return (index, name, result)
    }
}

do {
    let catalog = try JSONDecoder().decode(
        CatalogEnvelope.self,
        from: Data(contentsOf: catalogURL)
    )
    try require(catalog.themes.count == 200, "Catalog must contain exactly 200 themes.")

    let audit = try String(contentsOf: auditURL, encoding: .utf8)
    let rows = try auditRows(in: audit)
    try require(rows.count == 100, "Lineage audit must contain exactly 100 result rows.")

    for (offset, row) in rows.enumerated() {
        let expectedIndex = offset + 1
        try require(row.0 == expectedIndex, "Audit row numbering drifted at row \(expectedIndex).")
        try require(
            row.1 == catalog.themes[offset].displayName,
            "Audit row \(expectedIndex) does not match catalog theme \(catalog.themes[offset].displayName)."
        )
    }

    let repairedRows = rows.filter { $0.2 != "Pass" }.count
    try require(repairedRows == 63, "Expected 63 repaired lineage rows, found \(repairedRows).")

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
        .filter {
            $0.range(
                of: #"(?:audit-raw(?:-v[0-9]+)?|readme-(?:continuity|distinction)-raw)\.png$"#,
                options: .regularExpression
            ) != nil
        }
    try require(replacementFiles.count == 83, "Expected 83 raw repair candidates, found \(replacementFiles.count).")

    let uniqueTargets = Set(replacementFiles.map { path in
        path.replacingOccurrences(
            of: #"-(?:audit-raw(?:-v[0-9]+)?|readme-(?:continuity|distinction)-raw)\.png$"#,
            with: "",
            options: .regularExpression
        )
    })
    try require(uniqueTargets.count == 80, "Expected 80 unique repair targets, found \(uniqueTargets.count).")

    let expectedSheets = Set((1...20).map { String(format: "lineage-audit-%02d.png", $0) })
    let actualSheets = Set(try fileManager.contentsOfDirectory(atPath: sheetsURL.path))
    try require(actualSheets == expectedSheets, "Final lineage audit sheet set is incomplete or contains drift.")

    let expansionAudit = try String(contentsOf: expansionAuditURL, encoding: .utf8)
    let expansionRows = try auditRows(in: expansionAudit)
    try require(expansionRows.count == 100, "Expansion audit must contain exactly 100 result rows.")
    for (offset, row) in expansionRows.enumerated() {
        let expectedIndex = offset + 101
        try require(row.0 == expectedIndex, "Expansion audit row numbering drifted at row \(expectedIndex).")
        try require(
            row.1 == catalog.themes[offset + 100].displayName,
            "Expansion audit row \(expectedIndex) does not match catalog theme \(catalog.themes[offset + 100].displayName)."
        )
    }
    let expansionRepairedRows = expansionRows.filter { $0.2 != "Pass" }.count
    try require(expansionRepairedRows == 17, "Expected 17 repaired expansion rows, found \(expansionRepairedRows).")

    let progress = try JSONDecoder().decode(
        ExpansionProgress.self,
        from: Data(contentsOf: expansionRoot.appendingPathComponent("progress.json"))
    )
    for values in [progress.generatedLineups, progress.processedLineages, progress.reviewedLineages] {
        try require(values.count == 100 && Set(values).count == 100, "Expansion progress is not complete and unique.")
    }

    let expectedExpansionSheets = Set((1...20).map { String(format: "assets-%02d.jpg", $0) })
    let actualExpansionSheets = Set(
        try fileManager.contentsOfDirectory(atPath: expansionRoot.appendingPathComponent("ReviewSheets").path)
            .filter { $0.hasPrefix("assets-") && $0.hasSuffix(".jpg") }
    )
    try require(
        actualExpansionSheets == expectedExpansionSheets,
        "Expansion asset review sheet set is incomplete or contains drift."
    )

    print(
        "Verified 200 individual lineage audit rows: 100 legacy rows with 63 repaired lineages, "
            + "83 raw candidates and 20 sheets; plus 100 expansion rows with 17 repaired lineages "
            + "and 20 final asset sheets."
    )
} catch {
    fputs("Lineage audit verification failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
