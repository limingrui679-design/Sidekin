import CryptoKit
import Foundation

guard CommandLine.arguments.count == 3 || CommandLine.arguments.count == 4 else {
    fputs(
        "Usage: swift generate-release-manifest.swift app-path output.json [archive.zip]\n",
        stderr
    )
    exit(2)
}

struct FileRecord: Codable {
    let path: String
    let bytes: Int64
    let sha256: String
}

struct ArchiveRecord: Codable {
    let fileName: String
    let bytes: Int64
    let sha256: String
}

struct ReleaseManifest: Codable {
    let schemaVersion: Int
    let generatedAt: String
    let product: String
    let displayName: String
    let version: String
    let build: String
    let bundleIdentifier: String
    let minimumMacOS: String
    let architectures: [String]
    let sourceCommit: String?
    let sourceDirty: Bool?
    let signatureAuthority: String
    let teamIdentifier: String?
    let hardenedRuntime: Bool
    let appTreeSHA256: String
    let appFiles: [FileRecord]
    let characterAssets: [FileRecord]
    let archive: ArchiveRecord?
}

enum ManifestError: LocalizedError {
    case missingApp
    case missingInfoPlist
    case invalidInfoPlist
    case missingExecutable
    case invalidCharacterCount(Int)

    var errorDescription: String? {
        switch self {
        case .missingApp: "App bundle does not exist."
        case .missingInfoPlist: "App bundle is missing Contents/Info.plist."
        case .invalidInfoPlist: "App Info.plist is invalid or incomplete."
        case .missingExecutable: "App bundle is missing its main executable."
        case let .invalidCharacterCount(count): "Expected 50 character assets, found \(count)."
        }
    }
}

private func sha256(url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
        hasher.update(data: data)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

private func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (
            process.terminationStatus,
            String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
    } catch {
        return (127, error.localizedDescription)
    }
}

private func value(after prefix: String, in lines: [Substring]) -> String? {
    guard let line = lines.first(where: { $0.hasPrefix(prefix) }) else { return nil }
    return String(line.dropFirst(prefix.count))
}

private func records(in appURL: URL) throws -> [FileRecord] {
    let fileManager = FileManager.default
    var result: [FileRecord] = []
    for relativePath in try fileManager.subpathsOfDirectory(atPath: appURL.path).sorted() {
        let url = appURL.appendingPathComponent(relativePath)
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { continue }
        result.append(FileRecord(
            path: relativePath,
            bytes: Int64(values.fileSize ?? 0),
            sha256: try sha256(url: url)
        ))
    }
    return result
}

private func treeHash(_ files: [FileRecord]) -> String {
    var hasher = SHA256()
    for file in files {
        hasher.update(data: Data(file.path.utf8))
        hasher.update(data: Data([0]))
        hasher.update(data: Data(file.sha256.utf8))
        hasher.update(data: Data([0]))
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

do {
    let appURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        .standardizedFileURL
        .resolvingSymlinksInPath()
    let outputURL = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL
    let archiveURL = CommandLine.arguments.count == 4
        ? URL(fileURLWithPath: CommandLine.arguments[3]).standardizedFileURL
        : nil
    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: appURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
        throw ManifestError.missingApp
    }

    let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
    guard fileManager.fileExists(atPath: infoURL.path) else {
        throw ManifestError.missingInfoPlist
    }
    guard let plist = try PropertyListSerialization.propertyList(
        from: Data(contentsOf: infoURL),
        options: [],
        format: nil
    ) as? [String: Any],
          let executableName = plist["CFBundleExecutable"] as? String,
          let version = plist["CFBundleShortVersionString"] as? String,
          let build = plist["CFBundleVersion"] as? String,
          let bundleIdentifier = plist["CFBundleIdentifier"] as? String,
          let minimumMacOS = plist["LSMinimumSystemVersion"] as? String
    else { throw ManifestError.invalidInfoPlist }

    let executableURL = appURL.appendingPathComponent("Contents/MacOS/\(executableName)")
    guard fileManager.fileExists(atPath: executableURL.path) else {
        throw ManifestError.missingExecutable
    }
    let architectureResult = run("/usr/bin/lipo", ["-archs", executableURL.path])
    let architectures = architectureResult.status == 0
        ? architectureResult.output.split(separator: " ").map(String.init)
        : []

    let signatureResult = run("/usr/bin/codesign", ["-dv", "--verbose=4", appURL.path])
    let signatureLines = signatureResult.output.split(separator: "\n")
    let authority = value(after: "Authority=", in: signatureLines)
        ?? value(after: "Signature=", in: signatureLines)
        ?? "unknown"
    let rawTeam = value(after: "TeamIdentifier=", in: signatureLines)
    let teamIdentifier = rawTeam == "not set" ? nil : rawTeam
    let hardenedRuntime = signatureLines.contains { line in
        line.hasPrefix("flags=") && line.contains("runtime")
    }

    let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let commitResult = run("/usr/bin/git", ["-C", projectRoot.path, "rev-parse", "HEAD"])
    let statusResult = run("/usr/bin/git", ["-C", projectRoot.path, "status", "--porcelain"])
    let sourceCommit = commitResult.status == 0 ? commitResult.output : nil
    let sourceDirty = statusResult.status == 0 ? !statusResult.output.isEmpty : nil

    let appFiles = try records(in: appURL)
    let characterAssets = appFiles.filter { file in
        file.path.contains("CainiaoPet_CainiaoPetApp.bundle/")
            && file.path.hasSuffix(".png")
    }
    guard characterAssets.count == 50 else {
        throw ManifestError.invalidCharacterCount(characterAssets.count)
    }

    let archive: ArchiveRecord?
    if let archiveURL {
        let values = try archiveURL.resourceValues(forKeys: [.fileSizeKey])
        archive = ArchiveRecord(
            fileName: archiveURL.lastPathComponent,
            bytes: Int64(values.fileSize ?? 0),
            sha256: try sha256(url: archiveURL)
        )
    } else {
        archive = nil
    }

    let manifest = ReleaseManifest(
        schemaVersion: 1,
        generatedAt: ISO8601DateFormatter().string(from: Date()),
        product: plist["CFBundleName"] as? String ?? "CainiaoPet",
        displayName: plist["CFBundleDisplayName"] as? String ?? "CainiaoPet",
        version: version,
        build: build,
        bundleIdentifier: bundleIdentifier,
        minimumMacOS: minimumMacOS,
        architectures: architectures,
        sourceCommit: sourceCommit,
        sourceDirty: sourceDirty,
        signatureAuthority: authority,
        teamIdentifier: teamIdentifier,
        hardenedRuntime: hardenedRuntime,
        appTreeSHA256: treeHash(appFiles),
        appFiles: appFiles,
        characterAssets: characterAssets,
        archive: archive
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(manifest)
    try fileManager.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try data.write(to: outputURL, options: .atomic)
    print("Wrote \(outputURL.path)")
} catch {
    fputs("Release manifest failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
