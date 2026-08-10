import CainiaoPetCore
import Foundation

public enum PetGenerationJobState: String, Codable, Sendable {
    case ready
    case running
    case failed
    case cancelled

    public var displayName: String {
        switch self {
        case .ready: "等待继续"
        case .running: "上次生成被中断"
        case .failed: "生成失败，可重试"
        case .cancelled: "已暂停，可继续"
        }
    }
}

public struct PetGenerationJob: Codable, Equatable, Identifiable, Sendable {
    public var schemaVersion: Int
    public var id: String
    public var templateID: String
    public var templateName: String
    public var description: String
    public var artDirection: String
    public var mode: PetTemplateGenerationMode
    public var quality: PetImageGenerationQuality
    public var stageNames: [String]
    public var referenceFileName: String?
    public var fallbackTheme: PetVisualTheme
    public var createdAt: Date
    public var updatedAt: Date
    public var completedStages: [CustomPetStageDefinition]
    public var state: PetGenerationJobState
    public var lastError: String?

    public init(
        schemaVersion: Int = 1,
        id: String = UUID().uuidString,
        templateID: String = UUID().uuidString,
        templateName: String,
        description: String,
        artDirection: String,
        mode: PetTemplateGenerationMode,
        quality: PetImageGenerationQuality,
        stageNames: [String],
        referenceFileName: String? = nil,
        fallbackTheme: PetVisualTheme,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        completedStages: [CustomPetStageDefinition] = [],
        state: PetGenerationJobState = .ready,
        lastError: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.templateID = templateID
        self.templateName = templateName
        self.description = description
        self.artDirection = artDirection
        self.mode = mode
        self.quality = quality
        self.stageNames = stageNames
        self.referenceFileName = referenceFileName
        self.fallbackTheme = fallbackTheme
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedStages = completedStages.sorted { $0.index < $1.index }
        self.state = state
        self.lastError = lastError
    }

    public var completedCount: Int { completedStages.count }

    public var nextStageIndex: Int {
        let completed = Set(completedStages.map(\.index))
        return stageNames.indices.first { !completed.contains($0) } ?? stageNames.count
    }

    public var request: PetGenerationRequest {
        PetGenerationRequest(
            templateName: templateName,
            description: description,
            artDirection: artDirection,
            mode: mode,
            quality: quality,
            stageNames: stageNames,
            referenceImage: nil,
            fallbackTheme: fallbackTheme
        )
    }
}

public enum PetGenerationJobStoreError: LocalizedError {
    case invalidJobID
    case jobNotFound
    case jobAlreadyExists
    case invalidJob
    case invalidStageIndex

    public var errorDescription: String? {
        switch self {
        case .invalidJobID: "生成任务标识无效。"
        case .jobNotFound: "没有找到可继续的生成任务。"
        case .jobAlreadyExists: "生成任务目录已经存在。"
        case .invalidJob: "生成任务数据已损坏。"
        case .invalidStageIndex: "生成阶段序号无效。"
        }
    }
}

public struct PetGenerationJobStore {
    public let jobsDirectory: URL
    private let fileManager: FileManager

    public init(
        jobsDirectory: URL = CainiaoPetPaths.generationJobsDirectory(),
        fileManager: FileManager = .default
    ) {
        self.jobsDirectory = jobsDirectory
        self.fileManager = fileManager
    }

    public func loadAll() throws -> [PetGenerationJob] {
        guard fileManager.fileExists(atPath: jobsDirectory.path) else { return [] }
        let directories = try fileManager.contentsOfDirectory(
            at: jobsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return directories.compactMap { directory in
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return nil
            }
            return try? loadJob(at: directory)
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func load(id: String) throws -> PetGenerationJob {
        let directory = try jobDirectory(id: id)
        guard fileManager.fileExists(atPath: directory.path) else {
            throw PetGenerationJobStoreError.jobNotFound
        }
        return try loadJob(at: directory)
    }

    @discardableResult
    public func create(
        request: PetGenerationRequest,
        normalizedReference: Data?
    ) throws -> PetGenerationJob {
        let now = Date()
        let job = PetGenerationJob(
            templateName: request.templateName,
            description: request.description,
            artDirection: request.artDirection,
            mode: request.mode,
            quality: request.quality,
            stageNames: request.stageNames,
            referenceFileName: normalizedReference == nil ? nil : "reference.png",
            fallbackTheme: request.fallbackTheme,
            createdAt: now,
            updatedAt: now
        )
        try fileManager.createDirectory(at: jobsDirectory, withIntermediateDirectories: true)
        let finalDirectory = try jobDirectory(id: job.id)
        guard !fileManager.fileExists(atPath: finalDirectory.path) else {
            throw PetGenerationJobStoreError.jobAlreadyExists
        }
        let stagingDirectory = jobsDirectory
            .appendingPathComponent(".staging-\(job.id)-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        do {
            if let normalizedReference {
                try normalizedReference.write(
                    to: stagingDirectory.appendingPathComponent("reference.png"),
                    options: .atomic
                )
            }
            try encode(job).write(
                to: stagingDirectory.appendingPathComponent("job.json"),
                options: .atomic
            )
            try fileManager.moveItem(at: stagingDirectory, to: finalDirectory)
            return job
        } catch {
            try? fileManager.removeItem(at: stagingDirectory)
            throw error
        }
    }

    public func referenceData(jobID: String) throws -> Data? {
        let job = try load(id: jobID)
        guard let fileName = job.referenceFileName else { return nil }
        let url = try jobDirectory(id: jobID).appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: url.path) else {
            throw PetGenerationJobStoreError.invalidJob
        }
        return try Data(contentsOf: url)
    }

    public func rawStageData(jobID: String, stageIndex: Int) throws -> Data? {
        try stageData(jobID: jobID, stageIndex: stageIndex, raw: true)
    }

    public func processedStageData(jobID: String, stageIndex: Int) throws -> Data? {
        try stageData(jobID: jobID, stageIndex: stageIndex, raw: false)
    }

    public func processedStageURL(jobID: String, stageIndex: Int) -> URL? {
        guard let directory = try? jobDirectory(id: jobID), stageIndex >= 0 else { return nil }
        let url = directory.appendingPathComponent(Self.processedFileName(stageIndex))
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    /// The API response is persisted before any image processing so a paid
    /// result can be recovered locally even if processing or the app fails.
    public func saveRawStage(jobID: String, stageIndex: Int, data: Data) throws {
        guard !data.isEmpty else { throw PetGenerationJobStoreError.invalidJob }
        let job = try load(id: jobID)
        guard job.stageNames.indices.contains(stageIndex) else {
            throw PetGenerationJobStoreError.invalidStageIndex
        }
        try data.write(
            to: try jobDirectory(id: jobID).appendingPathComponent(Self.rawFileName(stageIndex)),
            options: .atomic
        )
    }

    @discardableResult
    public func saveProcessedStage(
        jobID: String,
        definition: CustomPetStageDefinition,
        data: Data
    ) throws -> PetGenerationJob {
        guard !data.isEmpty else { throw PetGenerationJobStoreError.invalidJob }
        var job = try load(id: jobID)
        guard job.stageNames.indices.contains(definition.index),
              definition.assetFileName == Self.processedFileName(definition.index)
        else { throw PetGenerationJobStoreError.invalidStageIndex }

        try data.write(
            to: try jobDirectory(id: jobID).appendingPathComponent(definition.assetFileName),
            options: .atomic
        )
        job.completedStages.removeAll { $0.index == definition.index }
        job.completedStages.append(definition)
        job.completedStages.sort { $0.index < $1.index }
        job.updatedAt = Date()
        job.lastError = nil
        try write(job)
        return job
    }

    @discardableResult
    public func updateState(
        jobID: String,
        state: PetGenerationJobState,
        errorMessage: String? = nil
    ) throws -> PetGenerationJob {
        var job = try load(id: jobID)
        job.state = state
        job.lastError = errorMessage
        job.updatedAt = Date()
        try write(job)
        return job
    }

    @discardableResult
    public func restart(jobID: String, fromStage stageIndex: Int) throws -> PetGenerationJob {
        var job = try load(id: jobID)
        guard job.stageNames.indices.contains(stageIndex) else {
            throw PetGenerationJobStoreError.invalidStageIndex
        }
        let directory = try jobDirectory(id: jobID)
        for index in stageIndex..<job.stageNames.count {
            for name in [Self.rawFileName(index), Self.processedFileName(index)] {
                let url = directory.appendingPathComponent(name)
                if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
            }
        }
        job.completedStages.removeAll { $0.index >= stageIndex }
        job.state = .ready
        job.lastError = nil
        job.updatedAt = Date()
        try write(job)
        return job
    }

    public func remove(id: String) throws {
        let directory = try jobDirectory(id: id)
        guard fileManager.fileExists(atPath: directory.path) else {
            throw PetGenerationJobStoreError.jobNotFound
        }
        try fileManager.removeItem(at: directory)
    }

    private func stageData(jobID: String, stageIndex: Int, raw: Bool) throws -> Data? {
        let job = try load(id: jobID)
        guard job.stageNames.indices.contains(stageIndex) else {
            throw PetGenerationJobStoreError.invalidStageIndex
        }
        let name = raw ? Self.rawFileName(stageIndex) : Self.processedFileName(stageIndex)
        let url = try jobDirectory(id: jobID).appendingPathComponent(name)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    private func loadJob(at directory: URL) throws -> PetGenerationJob {
        let data = try Data(contentsOf: directory.appendingPathComponent("job.json"))
        let job = try Self.decoder.decode(PetGenerationJob.self, from: data)
        guard job.schemaVersion == 1,
              UUID(uuidString: job.id) != nil,
              UUID(uuidString: job.templateID) != nil,
              (CustomGrowthStagePlan.minimumStageCount...CustomGrowthStagePlan.maximumStageCount)
                .contains(job.stageNames.count),
              job.completedStages.allSatisfy({ job.stageNames.indices.contains($0.index) })
        else { throw PetGenerationJobStoreError.invalidJob }
        return job
    }

    private func write(_ job: PetGenerationJob) throws {
        try encode(job).write(
            to: try jobDirectory(id: job.id).appendingPathComponent("job.json"),
            options: .atomic
        )
    }

    private func encode(_ job: PetGenerationJob) throws -> Data {
        try Self.encoder.encode(job)
    }

    private func jobDirectory(id: String) throws -> URL {
        guard UUID(uuidString: id) != nil else {
            throw PetGenerationJobStoreError.invalidJobID
        }
        return jobsDirectory.appendingPathComponent(id, isDirectory: true)
    }

    private static func rawFileName(_ index: Int) -> String {
        String(format: "raw-stage-%02d.png", index + 1)
    }

    private static func processedFileName(_ index: Int) -> String {
        String(format: "stage-%02d.png", index + 1)
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
