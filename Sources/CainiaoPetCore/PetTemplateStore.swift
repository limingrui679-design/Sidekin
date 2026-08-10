import Foundation

public enum PetTemplateStoreError: LocalizedError, Equatable {
    case invalidTemplateID
    case invalidStageCount
    case invalidStageLayout
    case imageCountMismatch
    case templateAlreadyExists
    case templateNotFound
    case invalidName
    case invalidPackage
    case stageIndexOutOfRange

    public var errorDescription: String? {
        switch self {
        case .invalidTemplateID: "宠物模板标识无效。"
        case .invalidStageCount: "成长阶段必须在 1 到 8 之间。"
        case .invalidStageLayout: "成长阶段顺序或资源文件名无效。"
        case .imageCountMismatch: "生成图片数量与成长阶段数量不一致。"
        case .templateAlreadyExists: "同名模板目录已经存在。"
        case .templateNotFound: "没有找到这个宠物模板。"
        case .invalidName: "模板名称不能为空，且最多为 40 个字符。"
        case .invalidPackage: "这不是有效的 CainiaoPet 模板包。"
        case .stageIndexOutOfRange: "成长阶段序号超出范围。"
        }
    }
}

private struct PetTemplatePackage: Codable {
    struct Asset: Codable {
        var fileName: String
        var data: Data
    }

    var schemaVersion: Int
    var template: CustomPetTemplate
    var stageAssets: [Asset]
    var referenceAsset: Asset?
}

public struct PetTemplateStore {
    public let templatesDirectory: URL
    private let fileManager: FileManager

    public init(
        templatesDirectory: URL = CainiaoPetPaths.petTemplatesDirectory(),
        fileManager: FileManager = .default
    ) {
        self.templatesDirectory = templatesDirectory
        self.fileManager = fileManager
    }

    public func loadAll() throws -> [CustomPetTemplate] {
        guard fileManager.fileExists(atPath: templatesDirectory.path) else { return [] }
        let directories = try fileManager.contentsOfDirectory(
            at: templatesDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return directories.compactMap { directory in
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return nil
            }
            return try? loadTemplate(at: directory)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    public func load(id: String) throws -> CustomPetTemplate? {
        guard let directory = try? templateDirectory(id: id),
              fileManager.fileExists(atPath: directory.path)
        else { return nil }
        return try loadTemplate(at: directory)
    }

    public func assetURL(templateID: String, fileName: String) -> URL? {
        guard isSafeFileName(fileName),
              let directory = try? templateDirectory(id: templateID)
        else { return nil }
        let url = directory.appendingPathComponent(fileName)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    public func assetData(templateID: String, fileName: String) throws -> Data {
        guard let url = assetURL(templateID: templateID, fileName: fileName) else {
            throw PetTemplateStoreError.invalidStageLayout
        }
        return try Data(contentsOf: url)
    }

    public func referenceData(template: CustomPetTemplate) throws -> Data? {
        guard let fileName = template.referenceFileName else { return nil }
        return try assetData(templateID: template.id, fileName: fileName)
    }

    @discardableResult
    public func install(
        template: CustomPetTemplate,
        stageImages: [Data],
        referenceImage: Data? = nil
    ) throws -> CustomPetTemplate {
        try validate(template)
        guard stageImages.count == template.stages.count else {
            throw PetTemplateStoreError.imageCountMismatch
        }

        try fileManager.createDirectory(at: templatesDirectory, withIntermediateDirectories: true)
        let finalDirectory = try templateDirectory(id: template.id)
        guard !fileManager.fileExists(atPath: finalDirectory.path) else {
            throw PetTemplateStoreError.templateAlreadyExists
        }

        let stagingDirectory = templatesDirectory
            .appendingPathComponent(".staging-\(template.id)-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)

        do {
            for (stage, imageData) in zip(template.stages, stageImages) {
                try imageData.write(
                    to: stagingDirectory.appendingPathComponent(stage.assetFileName),
                    options: .atomic
                )
            }

            if let referenceImage,
               let referenceFileName = template.referenceFileName {
                guard isSafeFileName(referenceFileName) else {
                    throw PetTemplateStoreError.invalidStageLayout
                }
                try referenceImage.write(
                    to: stagingDirectory.appendingPathComponent(referenceFileName),
                    options: .atomic
                )
            }

            let manifestData = try Self.encoder.encode(template)
            try manifestData.write(
                to: stagingDirectory.appendingPathComponent("template.json"),
                options: .atomic
            )
            try fileManager.moveItem(at: stagingDirectory, to: finalDirectory)
            return template
        } catch {
            try? fileManager.removeItem(at: stagingDirectory)
            throw error
        }
    }

    @discardableResult
    public func rename(id: String, to rawName: String) throws -> CustomPetTemplate {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 40 else {
            throw PetTemplateStoreError.invalidName
        }
        guard var template = try load(id: id) else {
            throw PetTemplateStoreError.templateNotFound
        }
        template.name = name
        try writeManifest(template)
        return template
    }

    public func remove(id: String) throws {
        let directory = try templateDirectory(id: id)
        guard fileManager.fileExists(atPath: directory.path) else {
            throw PetTemplateStoreError.templateNotFound
        }
        try fileManager.removeItem(at: directory)
    }

    public func pendingReplacementRaw(
        templateID: String,
        stageIndex: Int
    ) throws -> Data? {
        let url = try pendingReplacementURL(templateID: templateID, stageIndex: stageIndex)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return data.isEmpty ? nil : data
    }

    public func savePendingReplacementRaw(
        templateID: String,
        stageIndex: Int,
        data: Data
    ) throws {
        guard !data.isEmpty else { throw PetTemplateStoreError.invalidStageLayout }
        let url = try pendingReplacementURL(templateID: templateID, stageIndex: stageIndex)
        try data.write(to: url, options: .atomic)
    }

    public func clearPendingReplacementRaw(
        templateID: String,
        stageIndex: Int
    ) throws {
        let url = try pendingReplacementURL(templateID: templateID, stageIndex: stageIndex)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    @discardableResult
    public func replaceStageImage(
        templateID: String,
        stageIndex: Int,
        imageData: Data,
        prompt: String? = nil,
        generationQuality: PetImageGenerationQuality? = nil
    ) throws -> CustomPetTemplate {
        guard !imageData.isEmpty else { throw PetTemplateStoreError.invalidStageLayout }
        guard var template = try load(id: templateID) else {
            throw PetTemplateStoreError.templateNotFound
        }
        guard template.stages.indices.contains(stageIndex) else {
            throw PetTemplateStoreError.stageIndexOutOfRange
        }

        let stageURL = try templateDirectory(id: templateID)
            .appendingPathComponent(template.stages[stageIndex].assetFileName)
        try imageData.write(to: stageURL, options: .atomic)
        if let prompt { template.stages[stageIndex].prompt = prompt }
        if let generationQuality { template.generationQuality = generationQuality }
        try writeManifest(template)
        return template
    }

    public func exportPackage(id: String) throws -> Data {
        guard let template = try load(id: id) else {
            throw PetTemplateStoreError.templateNotFound
        }
        let stageAssets = try template.stages.map { stage in
            PetTemplatePackage.Asset(
                fileName: stage.assetFileName,
                data: try assetData(templateID: template.id, fileName: stage.assetFileName)
            )
        }
        let referenceAsset: PetTemplatePackage.Asset?
        if let referenceFileName = template.referenceFileName {
            referenceAsset = PetTemplatePackage.Asset(
                fileName: referenceFileName,
                data: try assetData(templateID: template.id, fileName: referenceFileName)
            )
        } else {
            referenceAsset = nil
        }

        let package = PetTemplatePackage(
            schemaVersion: 1,
            template: template,
            stageAssets: stageAssets,
            referenceAsset: referenceAsset
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(package)
    }

    @discardableResult
    public func importPackage(_ data: Data) throws -> CustomPetTemplate {
        guard !data.isEmpty, data.count <= 128 * 1_024 * 1_024,
              let package = try? PropertyListDecoder().decode(PetTemplatePackage.self, from: data),
              package.schemaVersion == 1
        else { throw PetTemplateStoreError.invalidPackage }

        var template = package.template
        let expectedNames = template.stages.map(\.assetFileName)
        let suppliedNames = package.stageAssets.map(\.fileName)
        guard suppliedNames == expectedNames,
              package.stageAssets.allSatisfy({ !$0.data.isEmpty && $0.data.count <= 32 * 1_024 * 1_024 }),
              package.referenceAsset?.fileName == template.referenceFileName,
              package.referenceAsset.map({ !$0.data.isEmpty && $0.data.count <= 32 * 1_024 * 1_024 }) ?? true
        else { throw PetTemplateStoreError.invalidPackage }

        if (try? load(id: template.id)) != nil {
            template.id = UUID().uuidString
            template.createdAt = Date()
        }
        do {
            return try install(
                template: template,
                stageImages: package.stageAssets.map(\.data),
                referenceImage: package.referenceAsset?.data
            )
        } catch is PetTemplateStoreError {
            throw PetTemplateStoreError.invalidPackage
        }
    }

    public func validate(_ template: CustomPetTemplate) throws {
        guard UUID(uuidString: template.id) != nil else {
            throw PetTemplateStoreError.invalidTemplateID
        }
        guard (CustomGrowthStagePlan.minimumStageCount...CustomGrowthStagePlan.maximumStageCount)
            .contains(template.stages.count) else {
            throw PetTemplateStoreError.invalidStageCount
        }

        let ordered = template.stages
        let indices = ordered.map(\.index)
        let expectedIndices = Array(0..<ordered.count)
        let thresholds = ordered.map(\.experienceThreshold)
        let expectedThresholds = thresholds.sorted()
        let filenamesAreSafe = ordered.allSatisfy { isSafeFileName($0.assetFileName) }
        let referenceIsSafe = template.referenceFileName.map(isSafeFileName) ?? true

        guard indices == expectedIndices,
              thresholds == expectedThresholds,
              thresholds.first == 0,
              filenamesAreSafe,
              referenceIsSafe,
              Set(ordered.map(\.assetFileName)).count == ordered.count
        else {
            throw PetTemplateStoreError.invalidStageLayout
        }
    }

    private func loadTemplate(at directory: URL) throws -> CustomPetTemplate {
        let manifestURL = directory.appendingPathComponent("template.json")
        let template = try Self.decoder.decode(
            CustomPetTemplate.self,
            from: Data(contentsOf: manifestURL)
        )
        try validate(template)

        guard template.stages.allSatisfy({ stage in
            fileManager.fileExists(
                atPath: directory.appendingPathComponent(stage.assetFileName).path
            )
        }) else {
            throw PetTemplateStoreError.invalidStageLayout
        }
        return template
    }

    private func writeManifest(_ template: CustomPetTemplate) throws {
        try validate(template)
        let directory = try templateDirectory(id: template.id)
        guard fileManager.fileExists(atPath: directory.path) else {
            throw PetTemplateStoreError.templateNotFound
        }
        let data = try Self.encoder.encode(template)
        try data.write(to: directory.appendingPathComponent("template.json"), options: .atomic)
    }

    private func pendingReplacementURL(
        templateID: String,
        stageIndex: Int
    ) throws -> URL {
        guard let template = try load(id: templateID) else {
            throw PetTemplateStoreError.templateNotFound
        }
        guard template.stages.indices.contains(stageIndex) else {
            throw PetTemplateStoreError.stageIndexOutOfRange
        }
        return try templateDirectory(id: templateID).appendingPathComponent(
            String(format: ".pending-stage-%02d.raw.png", stageIndex + 1)
        )
    }

    private func templateDirectory(id: String) throws -> URL {
        guard UUID(uuidString: id) != nil else {
            throw PetTemplateStoreError.invalidTemplateID
        }
        return templatesDirectory.appendingPathComponent(id, isDirectory: true)
    }

    private func isSafeFileName(_ fileName: String) -> Bool {
        !fileName.isEmpty
            && fileName == URL(fileURLWithPath: fileName).lastPathComponent
            && !fileName.contains("..")
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
