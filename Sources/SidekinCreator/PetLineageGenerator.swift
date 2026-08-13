import SidekinCore
import Foundation

public struct PetGenerationRequest: Sendable {
    public var templateName: String
    public var description: String
    public var artDirection: String
    public var mode: PetTemplateGenerationMode
    public var quality: PetImageGenerationQuality
    public var stageNames: [String]
    public var referenceImage: Data?
    public var fallbackTheme: PetVisualTheme

    public init(
        templateName: String,
        description: String,
        artDirection: String,
        mode: PetTemplateGenerationMode,
        quality: PetImageGenerationQuality = .medium,
        stageNames: [String],
        referenceImage: Data? = nil,
        fallbackTheme: PetVisualTheme = .nova
    ) {
        self.templateName = templateName
        self.description = description
        self.artDirection = artDirection
        self.mode = mode
        self.quality = quality
        self.stageNames = stageNames
        self.referenceImage = referenceImage
        self.fallbackTheme = fallbackTheme
    }
}

public enum PetLineageGeneratorError: LocalizedError {
    case emptyName
    case emptyDescription
    case missingAPIKey
    case newRequestRequired
    case missingReference
    case invalidStageCount

    public var errorDescription: String? {
        switch self {
        case .emptyName: "Name the pet template before generating it."
        case .emptyDescription: "Describe the pet's species, silhouette, colors, or personality."
        case .missingAPIKey: "A new image request requires your own OpenAI API key."
        case .newRequestRequired: "All saved local images have been processed. The remaining stages require new API requests."
        case .missingReference: "This generation mode requires a reference image."
        case .invalidStageCount: "A growth line must contain between 1 and 8 stages."
        }
    }
}

@MainActor
public final class PetLineageGenerator {
    private let client: OpenAIImageClient
    private let store: PetTemplateStore
    private let jobStore: PetGenerationJobStore

    public init(
        client: OpenAIImageClient = OpenAIImageClient(),
        store: PetTemplateStore = PetTemplateStore(),
        jobStore: PetGenerationJobStore = PetGenerationJobStore()
    ) {
        self.client = client
        self.store = store
        self.jobStore = jobStore
    }

    public func generate(
        request: PetGenerationRequest,
        apiKey: String,
        progress: @escaping @MainActor (_ completed: Int, _ total: Int, _ stageName: String) -> Void
    ) async throws -> CustomPetTemplate {
        let request = try validated(request, requiresEmbeddedReference: true)

        let normalizedReference: Data?
        if let referenceImage = request.referenceImage {
            normalizedReference = try await Task.detached(priority: .userInitiated) {
                try PetImageProcessor.normalizeReference(referenceImage)
            }.value
        } else {
            normalizedReference = nil
        }
        let job = try jobStore.create(
            request: request,
            normalizedReference: normalizedReference
        )
        return try await resume(jobID: job.id, apiKey: apiKey, progress: progress)
    }

    public func resume(
        jobID: String,
        apiKey: String? = nil,
        allowNewRequests: Bool = true,
        progress: @escaping @MainActor (_ completed: Int, _ total: Int, _ stageName: String) -> Void
    ) async throws -> CustomPetTemplate {
        var job = try jobStore.load(id: jobID)
        if let installed = try store.load(id: job.templateID) {
            try? jobStore.remove(id: job.id)
            return installed
        }

        let request = try validated(job.request, requiresEmbeddedReference: false)
        let normalizedReference = try jobStore.referenceData(jobID: job.id)
        if request.mode.requiresReferenceImage, normalizedReference == nil {
            throw PetLineageGeneratorError.missingReference
        }
        job = try jobStore.updateState(jobID: job.id, state: .running)
        let thresholds = CustomGrowthStagePlan.thresholds(count: request.stageNames.count)
        var rawStageImages: [Data] = []

        do {
            for index in request.stageNames.indices {
                try Task.checkCancellation()
                let stageName = cleanedStageName(request.stageNames[index], index: index)
                let prompt = Self.prompt(request: request, stageIndex: index, stageName: stageName)
                let definition = CustomPetStageDefinition(
                    index: index,
                    name: stageName,
                    prompt: prompt,
                    experienceThreshold: thresholds[index],
                    assetFileName: String(format: "stage-%02d.png", index + 1)
                )
                progress(job.completedCount, request.stageNames.count, stageName)

                if let savedRaw = try jobStore.rawStageData(jobID: job.id, stageIndex: index) {
                    rawStageImages.append(savedRaw)
                    if try jobStore.processedStageData(jobID: job.id, stageIndex: index) == nil {
                        let processed = try await process(savedRaw)
                        job = try jobStore.saveProcessedStage(
                            jobID: job.id,
                            definition: definition,
                            data: processed
                        )
                    } else if !job.completedStages.contains(where: { $0.index == index }) {
                        let processed = try jobStore.processedStageData(jobID: job.id, stageIndex: index)!
                        job = try jobStore.saveProcessedStage(
                            jobID: job.id,
                            definition: definition,
                            data: processed
                        )
                    }
                    progress(job.completedCount, request.stageNames.count, stageName)
                    continue
                }

                if let processed = try jobStore.processedStageData(jobID: job.id, stageIndex: index) {
                    // A crash may occur after the processed file is atomically
                    // written but before its manifest update. Preserve it and
                    // use it as the lineage anchor instead of charging again.
                    rawStageImages.append(processed)
                    job = try jobStore.saveProcessedStage(
                        jobID: job.id,
                        definition: definition,
                        data: processed
                    )
                    progress(job.completedCount, request.stageNames.count, stageName)
                    continue
                }

                guard allowNewRequests else {
                    throw PetLineageGeneratorError.newRequestRequired
                }
                let requestAPIKey = try requiredAPIKey(apiKey)
                let rawImage = try await requestStage(
                    request: request,
                    index: index,
                    prompt: prompt,
                    normalizedReference: normalizedReference,
                    lineageImages: rawStageImages,
                    apiKey: requestAPIKey
                )
                // Save before chroma-keying. A paid result survives cancellation,
                // processing failure, app termination, and a later resume.
                try jobStore.saveRawStage(jobID: job.id, stageIndex: index, data: rawImage)
                rawStageImages.append(rawImage)
                let processed = try await process(rawImage)
                job = try jobStore.saveProcessedStage(
                    jobID: job.id,
                    definition: definition,
                    data: processed
                )
                progress(job.completedCount, request.stageNames.count, stageName)
            }

            try Task.checkCancellation()
            job = try jobStore.load(id: job.id)
            let definitions = job.completedStages.sorted { $0.index < $1.index }
            guard definitions.count == request.stageNames.count else {
                throw PetGenerationJobStoreError.invalidJob
            }
            let processedImages = try definitions.map { definition -> Data in
                guard let data = try jobStore.processedStageData(
                    jobID: job.id,
                    stageIndex: definition.index
                ) else { throw PetGenerationJobStoreError.invalidJob }
                return data
            }
            let template = CustomPetTemplate(
                id: job.templateID,
                name: request.templateName,
                basePrompt: request.description,
                artDirection: request.artDirection,
                generationMode: request.mode,
                generationQuality: request.quality,
                referenceFileName: normalizedReference == nil ? nil : "reference.png",
                createdAt: job.createdAt,
                fallbackTheme: request.fallbackTheme,
                stages: definitions
            )
            let installed = try store.install(
                template: template,
                stageImages: processedImages,
                referenceImage: normalizedReference
            )
            try jobStore.remove(id: job.id)
            return installed
        } catch PetLineageGeneratorError.newRequestRequired {
            _ = try? jobStore.updateState(jobID: job.id, state: .ready)
            throw PetLineageGeneratorError.newRequestRequired
        } catch is CancellationError {
            _ = try? jobStore.updateState(jobID: job.id, state: .cancelled)
            throw CancellationError()
        } catch {
            if Task.isCancelled {
                _ = try? jobStore.updateState(jobID: job.id, state: .cancelled)
                throw CancellationError()
            }
            _ = try? jobStore.updateState(
                jobID: job.id,
                state: .failed,
                errorMessage: error.localizedDescription
            )
            throw error
        }
    }

    public func regenerateStage(
        templateID: String,
        stageIndex: Int,
        quality: PetImageGenerationQuality? = nil,
        apiKey: String? = nil,
        forceNewRequest: Bool = false
    ) async throws -> CustomPetTemplate {
        guard let template = try store.load(id: templateID) else {
            throw PetTemplateStoreError.templateNotFound
        }
        guard template.stages.indices.contains(stageIndex) else {
            throw PetTemplateStoreError.stageIndexOutOfRange
        }
        let selectedQuality = quality ?? template.resolvedGenerationQuality
        let request = PetGenerationRequest(
            templateName: template.name,
            description: template.basePrompt,
            artDirection: template.artDirection,
            mode: template.generationMode,
            quality: selectedQuality,
            stageNames: template.stages.map(\.name),
            referenceImage: nil,
            fallbackTheme: template.fallbackTheme
        )
        let reference = try store.referenceData(template: template)
        let prompt = Self.prompt(
            request: request,
            stageIndex: stageIndex,
            stageName: template.stages[stageIndex].name
        )
        var lineage: [Data] = []
        if stageIndex > 0, let first = template.stages.first {
            lineage.append(try store.assetData(templateID: template.id, fileName: first.assetFileName))
        }
        if stageIndex > 1 {
            let previous = template.stages[stageIndex - 1]
            lineage.append(try store.assetData(templateID: template.id, fileName: previous.assetFileName))
        }
        let raw: Data
        if !forceNewRequest, let savedRaw = try store.pendingReplacementRaw(
            templateID: template.id,
            stageIndex: stageIndex
        ) {
            raw = savedRaw
        } else {
            let requestAPIKey = try requiredAPIKey(apiKey)
            raw = try await requestStage(
                request: request,
                index: stageIndex,
                prompt: prompt,
                normalizedReference: reference,
                lineageImages: lineage,
                apiKey: requestAPIKey
            )
            // A paid single-stage result gets the same raw-first guarantee as
            // a complete lineage job. Retrying after processing failure does
            // not issue a second paid request.
            try store.savePendingReplacementRaw(
                templateID: template.id,
                stageIndex: stageIndex,
                data: raw
            )
        }
        let processed = try await process(raw)
        let updated = try store.replaceStageImage(
            templateID: template.id,
            stageIndex: stageIndex,
            imageData: processed,
            prompt: prompt,
            generationQuality: selectedQuality
        )
        try store.clearPendingReplacementRaw(
            templateID: template.id,
            stageIndex: stageIndex
        )
        return updated
    }

    private func requiredAPIKey(_ rawKey: String?) throws -> String {
        let key = rawKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty else { throw PetLineageGeneratorError.missingAPIKey }
        return key
    }

    public static func prompt(
        request: PetGenerationRequest,
        stageIndex: Int,
        stageName: String
    ) -> String {
        let total = request.stageNames.count
        let position = total == 1 ? 1.0 : Double(stageIndex) / Double(total - 1)
        let maturity: String
        switch position {
        case ..<0.20: maturity = "origin or hatch form with a compact silhouette and no mature anatomy"
        case ..<0.45: maturity = "young form with large readable features and its first distinctive movement anatomy"
        case ..<0.70: maturity = "adolescent form with a clearly changed body ratio and new functional appendages"
        case ..<0.95: maturity = "advanced form with a structural ability change and a more dynamic silhouette"
        default: maturity = "final apex form with one unmistakable new outer-silhouette structure"
        }

        let modeInstruction: String
        switch request.mode {
        case .text:
            modeInstruction = "Create an original species from the written concept. Keep lineage anchors consistent with the supplied earlier-stage references."
        case .restyle:
            modeInstruction = "Use the uploaded subject only as the identity reference, then deliberately reinterpret it in the requested new art direction. Keep the species recognizable but do not copy its original rendering style or background."
        case .faithful:
            modeInstruction = "Preserve the uploaded subject's identity, markings, palette, facial proportions, and signature silhouette as closely as possible. Change only what is necessary to express this growth stage and produce a clean game asset."
        }

        return """
        Generate exactly one full-body desktop pet character asset, centered and completely inside frame.
        Template name: \(request.templateName).
        Core creature description: \(request.description).
        Requested art direction: \(request.artDirection).
        Growth stage \(stageIndex + 1) of \(total), named “\(stageName)”: \(maturity).
        \(modeInstruction)

        The stage must have a genuinely different body proportion, silhouette, pose, and stage-specific anatomy—not the same pose with recoloring or extra accessories. Preserve at least two lineage anchors across stages. Use a readable competitive-game character design, strong silhouette, polished materials, and a distinct pose suited to this creature. One character only; no lineup, no extra creatures, no text, no lettering, no logo, no frame, no UI, no watermark, no floor, and no cast shadow. Use a perfectly flat, uniform #FF00FF magenta background with no gradient, texture, lighting, or magenta particles. Keep magenta out of the creature itself wherever possible.
        """
    }

    private func requestStage(
        request: PetGenerationRequest,
        index: Int,
        prompt: String,
        normalizedReference: Data?,
        lineageImages: [Data],
        apiKey: String
    ) async throws -> Data {
        if index == 0, request.mode == .text {
            return try await client.generate(
                prompt: prompt,
                apiKey: apiKey,
                quality: request.quality.rawValue
            )
        }
        var references: [OpenAIImageInput] = []
        if let normalizedReference {
            references.append(OpenAIImageInput(
                data: normalizedReference,
                fileName: "original-reference.png"
            ))
        }
        if let first = lineageImages.first {
            references.append(OpenAIImageInput(data: first, fileName: "lineage-anchor.png"))
        }
        if lineageImages.count > 1, let previous = lineageImages.last {
            references.append(OpenAIImageInput(data: previous, fileName: "previous-stage.png"))
        }
        if references.isEmpty {
            return try await client.generate(
                prompt: prompt,
                apiKey: apiKey,
                quality: request.quality.rawValue
            )
        }
        return try await client.edit(
            prompt: prompt,
            images: references,
            apiKey: apiKey,
            quality: request.quality.rawValue
        )
    }

    private func process(_ rawImage: Data) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            try PetImageProcessor.prepareGeneratedAsset(rawImage)
        }.value
    }

    private func validated(
        _ request: PetGenerationRequest,
        requiresEmbeddedReference: Bool
    ) throws -> PetGenerationRequest {
        var request = request
        request.templateName = request.templateName.trimmingCharacters(in: .whitespacesAndNewlines)
        request.description = request.description.trimmingCharacters(in: .whitespacesAndNewlines)
        request.artDirection = request.artDirection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.templateName.isEmpty else { throw PetLineageGeneratorError.emptyName }
        guard !request.description.isEmpty else { throw PetLineageGeneratorError.emptyDescription }
        guard (CustomGrowthStagePlan.minimumStageCount...CustomGrowthStagePlan.maximumStageCount)
            .contains(request.stageNames.count) else {
            throw PetLineageGeneratorError.invalidStageCount
        }
        if requiresEmbeddedReference,
           request.mode.requiresReferenceImage,
           request.referenceImage == nil {
            throw PetLineageGeneratorError.missingReference
        }
        request.stageNames = request.stageNames.indices.map {
            cleanedStageName(request.stageNames[$0], index: $0)
        }
        return request
    }

    private func cleanedStageName(_ rawName: String, index: Int) -> String {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Stage \(index + 1)" : String(name.prefix(18))
    }
}
