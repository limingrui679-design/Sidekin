import Foundation

public enum SidekinPaths {
    private static let productDirectoryName = "Sidekin"
    private static let legacyProductDirectoryName = "CainiaoPet"

    private static func baseApplicationSupportDirectory(
        fileManager: FileManager
    ) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    }

    public static func applicationSupportDirectory(
        fileManager: FileManager = .default
    ) -> URL {
        let base = baseApplicationSupportDirectory(fileManager: fileManager)
        return prepareApplicationSupportDirectory(in: base, fileManager: fileManager)
    }

    public static func prepareApplicationSupportDirectory(
        in base: URL,
        fileManager: FileManager = .default
    ) -> URL {
        let destination = base.appendingPathComponent(productDirectoryName, isDirectory: true)
        migrateLegacyApplicationSupportIfNeeded(
            from: base.appendingPathComponent(legacyProductDirectoryName, isDirectory: true),
            to: destination,
            fileManager: fileManager
        )
        return destination
    }

    public static func stateURL(fileManager: FileManager = .default) -> URL {
        applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("pet-state.json")
    }

    public static func eventInboxURL(fileManager: FileManager = .default) -> URL {
        applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("codex-events.jsonl")
    }

    public static func petTemplatesDirectory(fileManager: FileManager = .default) -> URL {
        applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("PetTemplates", isDirectory: true)
    }

    public static func generationJobsDirectory(fileManager: FileManager = .default) -> URL {
        applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("GenerationJobs", isDirectory: true)
    }

    public static func defaultCodexHooksURL(fileManager: FileManager = .default) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("hooks.json")
    }

    public static func defaultCodexSessionsURL(fileManager: FileManager = .default) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }

    private static func migrateLegacyApplicationSupportIfNeeded(
        from source: URL,
        to destination: URL,
        fileManager: FileManager
    ) {
        guard !fileManager.fileExists(atPath: destination.path),
              fileManager.fileExists(atPath: source.path)
        else { return }

        do {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(at: source, to: destination)
        } catch {
            // Migration is best-effort. Callers can still create a clean Sidekin directory.
        }
    }
}

public struct PetPersistence {
    public let stateURL: URL
    private let fileManager: FileManager

    public init(
        stateURL: URL = SidekinPaths.stateURL(),
        fileManager: FileManager = .default
    ) {
        self.stateURL = stateURL
        self.fileManager = fileManager
    }

    public func load() throws -> PetSnapshot? {
        guard fileManager.fileExists(atPath: stateURL.path) else { return nil }
        let data = try Data(contentsOf: stateURL)
        return try Self.decoder.decode(PetSnapshot.self, from: data)
    }

    public func save(_ snapshot: PetSnapshot) throws {
        let directory = stateURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(snapshot)
        try data.write(to: stateURL, options: .atomic)
    }

    public func remove() throws {
        guard fileManager.fileExists(atPath: stateURL.path) else { return }
        try fileManager.removeItem(at: stateURL)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
