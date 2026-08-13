import AppKit
import SidekinCore
import SidekinCreator
import Combine
import Foundation

extension Notification.Name {
    static let sidekinVisibilityChanged = Notification.Name("SidekinVisibilityChanged")
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var pet: PetSnapshot
    @Published private(set) var customTemplates: [CustomPetTemplate]
    @Published private(set) var generationJobs: [PetGenerationJob]
    @Published var previewStage: PetStage?
    @Published var previewCustomStageIndex: Int?
    @Published var isPetVisible = true
    @Published private(set) var hooksInstalled = false
    @Published private(set) var hasImageAPIKey = false
    @Published private(set) var isGeneratingTemplate = false
    @Published private(set) var generationCompleted = 0
    @Published private(set) var generationTotal = 0
    @Published private(set) var generationStageName = ""
    @Published var bannerMessage: String?

    private let persistence: PetPersistence
    private let monitor: CodexSessionMonitor
    private let hooksInstaller = CodexHooksInstaller()
    private let templateStore: PetTemplateStore
    private let generationJobStore: PetGenerationJobStore
    private let apiKeyStore: OpenAIAPIKeyStore
    private let lineageGenerator: PetLineageGenerator
    private let preservesLaunchPreview: Bool
    private var clockTask: Task<Void, Never>?
    private var generationTask: Task<Void, Never>?
    private var lastSignal: (activity: CodexActivity, date: Date, eventID: String?)?

    init(
        persistence: PetPersistence = PetPersistence(),
        monitor: CodexSessionMonitor = CodexSessionMonitor(),
        templateStore: PetTemplateStore = PetTemplateStore(),
        generationJobStore: PetGenerationJobStore = PetGenerationJobStore(),
        apiKeyStore: OpenAIAPIKeyStore = OpenAIAPIKeyStore(),
        lineageGenerator: PetLineageGenerator? = nil
    ) {
        self.persistence = persistence
        self.monitor = monitor
        self.templateStore = templateStore
        self.generationJobStore = generationJobStore
        self.apiKeyStore = apiKeyStore
        self.lineageGenerator = lineageGenerator ?? PetLineageGenerator(
            store: templateStore,
            jobStore: generationJobStore
        )
        let loadedTemplates = (try? templateStore.loadAll()) ?? []
        self.customTemplates = loadedTemplates
        self.generationJobs = (try? generationJobStore.loadAll()) ?? []
        self.hasImageAPIKey = apiKeyStore.hasKey()

        let launchPreview = CommandLine.arguments
            .first { $0.hasPrefix("--preview-stage=") }
            .map { String($0.dropFirst("--preview-stage=".count)) }
            .flatMap(PetStage.init(rawValue:))
        self.previewStage = launchPreview
        self.previewCustomStageIndex = nil
        self.preservesLaunchPreview = launchPreview != nil

        do {
            var loaded = try persistence.load() ?? PetSnapshot()
            PetLifecycleEngine.advance(&loaded)
            if let selectedID = loaded.wardrobe.customTemplateID,
               !loadedTemplates.contains(where: { $0.id == selectedID }) {
                loaded.wardrobe.customTemplateID = nil
            }
            self.pet = loaded
        } catch {
            self.pet = PetSnapshot()
            self.bannerMessage = "The previous save could not be read, so a safe new save was created."
        }

        refreshHooksStatus()

        monitor.onActivity = { [weak self] activity, date, eventID in
            self?.receiveCodexActivity(activity, at: date, eventID: eventID)
        }
        monitor.start()

        clockTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                self?.advanceClock()
            }
        }
    }

    deinit {
        clockTask?.cancel()
        generationTask?.cancel()
    }

    var activeCustomTemplate: CustomPetTemplate? {
        guard let id = pet.wardrobe.customTemplateID else { return nil }
        return customTemplates.first { $0.id == id }
    }

    var activeTheme: PetVisualTheme {
        activeCustomTemplate?.fallbackTheme ?? pet.wardrobe.resolvedTheme
    }

    var activeCustomStageIndex: Int? {
        activeCustomTemplate?.stageIndex(for: pet.experience)
    }

    var displayedCustomStageIndex: Int? {
        guard let template = activeCustomTemplate else { return nil }
        return min(
            template.stages.count - 1,
            max(0, previewCustomStageIndex ?? template.stageIndex(for: pet.experience))
        )
    }

    var displayedStage: PetStage {
        if let template = activeCustomTemplate,
           let index = displayedCustomStageIndex {
            return CustomGrowthStagePlan.canonicalStage(
                customIndex: index,
                stageCount: template.stages.count
            )
        }
        return previewStage ?? pet.stage
    }

    var displayedAssetURL: URL? {
        guard let template = activeCustomTemplate,
              let index = displayedCustomStageIndex,
              template.stages.indices.contains(index)
        else { return nil }
        return templateStore.assetURL(
            templateID: template.id,
            fileName: template.stages[index].assetFileName
        )
    }

    var displayedFormName: String {
        if let template = activeCustomTemplate,
           let index = displayedCustomStageIndex,
           template.stages.indices.contains(index) {
            return template.stages[index].name
        }
        return activeTheme.formName(at: displayedStage)
    }

    var activeFormName: String {
        if let template = activeCustomTemplate {
            let index = template.stageIndex(for: pet.experience)
            return template.stages[index].name
        }
        return activeTheme.formName(at: pet.stage)
    }

    var displayedStageSubtitle: String {
        if let template = activeCustomTemplate,
           let index = displayedCustomStageIndex {
            return template.name + " · Stage " + String(index + 1)
                + " of " + String(template.stages.count)
        }
        return displayedStage.subtitle
    }

    var activeStageCount: Int {
        activeCustomTemplate?.stages.count ?? PetStage.allCases.count
    }

    var activeNextStageThreshold: Int? {
        guard let template = activeCustomTemplate else { return pet.nextStageThreshold }
        let index = template.stageIndex(for: pet.experience)
        let next = index + 1
        return template.stages.indices.contains(next)
            ? template.stages[next].experienceThreshold
            : nil
    }

    var activeStageProgress: Double {
        guard let template = activeCustomTemplate else { return pet.stageProgress }
        let index = template.stageIndex(for: pet.experience)
        guard template.stages.indices.contains(index + 1) else { return 1 }
        let lower = template.stages[index].experienceThreshold
        let upper = template.stages[index + 1].experienceThreshold
        guard upper > lower else { return 1 }
        return min(1, max(0, Double(pet.experience - lower) / Double(upper - lower)))
    }

    var hasActivePreview: Bool {
        previewStage != nil || previewCustomStageIndex != nil
    }

    var storageDescription: String { persistence.stateURL.path }
    var templatesDescription: String { templateStore.templatesDirectory.path }
    var generationJobsDescription: String { generationJobStore.jobsDirectory.path }
    var codexSessionsDescription: String { SidekinPaths.defaultCodexSessionsURL().path }

    func perform(_ action: PetCareAction) {
        PetLifecycleEngine.perform(action, on: &pet)
        if !preservesLaunchPreview { clearPreview() }

        switch action {
        case .feed: bannerMessage = "Sprout enjoyed the meal."
        case .play: bannerMessage = "Playtime lifted Sprout's mood."
        case .sleepOrWake:
            bannerMessage = pet.isSleeping ? "Sprout is asleep and recovering energy." : "Sprout is awake."
        }
        persist()
    }

    func choose(theme: PetVisualTheme) {
        pet.wardrobe.theme = theme
        pet.wardrobe.customTemplateID = nil
        clearPreview()
        bannerMessage = "Built-in theme enabled: " + theme.displayName + "."
        persist()
    }

    func activate(template: CustomPetTemplate) {
        pet.wardrobe.customTemplateID = template.id
        pet.wardrobe.theme = template.fallbackTheme
        clearPreview()
        bannerMessage = "Custom pet enabled: " + template.name + "."
        persist()
    }

    func generationPreviewURL(jobID: String, stageIndex: Int) -> URL? {
        generationJobStore.processedStageURL(jobID: jobID, stageIndex: stageIndex)
    }

    func generationRawPreviewURL(jobID: String, stageIndex: Int) -> URL? {
        generationJobStore.rawStageURL(jobID: jobID, stageIndex: stageIndex)
    }

    func setPreview(stage: PetStage?) {
        previewStage = stage
        previewCustomStageIndex = nil
    }

    func setPreview(customStageIndex: Int?) {
        previewCustomStageIndex = customStageIndex
        previewStage = nil
    }

    func clearPreview() {
        previewStage = nil
        previewCustomStageIndex = nil
    }

    func saveImageAPIKey(_ rawKey: String) {
        do {
            try apiKeyStore.save(rawKey)
            hasImageAPIKey = true
            bannerMessage = "The API key was saved securely in macOS Keychain."
        } catch {
            bannerMessage = error.localizedDescription
        }
    }

    func removeImageAPIKey() {
        do {
            try apiKeyStore.remove()
            hasImageAPIKey = false
            bannerMessage = "The API key was removed from macOS Keychain."
        } catch {
            bannerMessage = error.localizedDescription
        }
    }

    func beginTemplateGeneration(request: PetGenerationRequest, apiKey: String?) {
        guard !isGeneratingTemplate else { return }
        guard let key = resolvedImageAPIKey(supplied: apiKey) else { return }

        isGeneratingTemplate = true
        generationCompleted = 0
        generationTotal = request.stageNames.count
        generationStageName = request.stageNames.first ?? "Preparing"
        bannerMessage = "Creating " + String(request.stageNames.count) + " growth stages…"

        generationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let template = try await lineageGenerator.generate(
                    request: request,
                    apiKey: key
                ) { [weak self] completed, total, stageName in
                    self?.generationCompleted = completed
                    self?.generationTotal = total
                    self?.generationStageName = stageName
                    self?.refreshGenerationJobs()
                }
                reloadCustomTemplates()
                activate(template: template)
                bannerMessage = template.name + " was generated and enabled with "
                    + String(template.stages.count) + " growth stages."
            } catch is CancellationError {
                refreshGenerationJobs()
                bannerMessage = "Generation paused. Completed stages are saved locally and can be resumed later."
            } catch {
                refreshGenerationJobs()
                bannerMessage = Task.isCancelled
                    ? "Generation paused. Completed stages are saved locally and can be resumed later."
                    : "Generation failed: " + error.localizedDescription + " Completed stages remain saved locally."
            }
            isGeneratingTemplate = false
            generationTask = nil
        }
    }

    func cancelTemplateGeneration() {
        generationTask?.cancel()
    }

    func resumeTemplateGeneration(
        job: PetGenerationJob,
        apiKey: String? = nil,
        allowNewRequests: Bool = true
    ) {
        guard !isGeneratingTemplate else { return }
        // A saved paid result can be reprocessed without a key. The generator
        // asks for a key only when it actually reaches an unsaved stage.
        let key = allowNewRequests
            ? resolvedImageAPIKey(supplied: apiKey, required: false)
            : nil
        isGeneratingTemplate = true
        generationCompleted = job.completedCount
        generationTotal = job.stageNames.count
        generationStageName = job.stageNames.indices.contains(job.nextStageIndex)
            ? job.stageNames[job.nextStageIndex]
            : "Finalizing template"
        bannerMessage = allowNewRequests
            ? "Resuming from stage " + String(min(job.stageNames.count, job.nextStageIndex + 1))
                + ". Saved stages will not be requested again."
            : "Processing only API images already saved on this Mac. No new request will be sent."

        generationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let template = try await lineageGenerator.resume(
                    jobID: job.id,
                    apiKey: key,
                    allowNewRequests: allowNewRequests
                ) { [weak self] completed, total, stageName in
                    self?.generationCompleted = completed
                    self?.generationTotal = total
                    self?.generationStageName = stageName
                    self?.refreshGenerationJobs()
                }
                reloadCustomTemplates()
                activate(template: template)
                bannerMessage = template.name + " finished resuming and is now enabled."
            } catch PetLineageGeneratorError.newRequestRequired {
                refreshGenerationJobs()
                bannerMessage = "All saved local images are processed. Later stages remain unrequested until you choose Continue Generation."
            } catch is CancellationError {
                refreshGenerationJobs()
                bannerMessage = "Generation paused. Previously generated paid stages remain saved locally."
            } catch {
                refreshGenerationJobs()
                bannerMessage = Task.isCancelled
                    ? "Generation paused. Previously generated paid stages remain saved locally."
                    : "Could not continue generation: " + error.localizedDescription
            }
            isGeneratingTemplate = false
            generationTask = nil
        }
    }

    func restartGenerationJob(_ job: PetGenerationJob, fromStage stageIndex: Int) {
        do {
            _ = try generationJobStore.restart(jobID: job.id, fromStage: stageIndex)
            refreshGenerationJobs()
            bannerMessage = "Stage \(stageIndex + 1) and all later results were cleared and can be generated again."
        } catch {
            bannerMessage = error.localizedDescription
        }
    }

    func discardGenerationJob(_ job: PetGenerationJob) {
        do {
            try generationJobStore.remove(id: job.id)
            refreshGenerationJobs()
            bannerMessage = "The unfinished generation job was deleted."
        } catch {
            bannerMessage = error.localizedDescription
        }
    }

    func renameTemplate(_ template: CustomPetTemplate, to name: String) {
        do {
            let updated = try templateStore.rename(id: template.id, to: name)
            reloadCustomTemplates()
            bannerMessage = "Template renamed to " + updated.name + "."
        } catch {
            bannerMessage = error.localizedDescription
        }
    }

    func deleteTemplate(_ template: CustomPetTemplate) {
        do {
            let wasActive = pet.wardrobe.customTemplateID == template.id
            try templateStore.remove(id: template.id)
            if wasActive {
                pet.wardrobe.customTemplateID = nil
                clearPreview()
                persist()
            }
            reloadCustomTemplates()
            bannerMessage = "Custom template deleted: " + template.name + "."
        } catch {
            bannerMessage = error.localizedDescription
        }
    }

    func exportTemplate(_ template: CustomPetTemplate, to url: URL) {
        do {
            let data = try templateStore.exportPackage(id: template.id)
            try data.write(to: url, options: .atomic)
            bannerMessage = "Template exported as " + url.lastPathComponent + "."
        } catch {
            bannerMessage = "Export failed: " + error.localizedDescription
        }
    }

    func importTemplate(from url: URL) {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard (values.fileSize ?? 0) <= 128 * 1_024 * 1_024 else {
                throw PetTemplateStoreError.invalidPackage
            }
            let template = try templateStore.importPackage(Data(contentsOf: url))
            reloadCustomTemplates()
            activate(template: template)
            bannerMessage = "Imported and enabled " + template.name + "."
        } catch {
            bannerMessage = "Import failed: " + error.localizedDescription
        }
    }

    func replaceTemplateStage(
        _ template: CustomPetTemplate,
        stageIndex: Int,
        with sourceData: Data
    ) {
        guard !isGeneratingTemplate else { return }
        isGeneratingTemplate = true
        generationCompleted = 0
        generationTotal = 1
        generationStageName = template.stages.indices.contains(stageIndex)
            ? template.stages[stageIndex].name
            : "Replace Stage"
        generationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let processed = try await Task.detached(priority: .userInitiated) {
                    try PetImageProcessor.prepareGeneratedAsset(sourceData)
                }.value
                _ = try templateStore.replaceStageImage(
                    templateID: template.id,
                    stageIndex: stageIndex,
                    imageData: processed
                )
                reloadCustomTemplates()
                generationCompleted = 1
                bannerMessage = "Replaced " + template.stages[stageIndex].name + " with a local image."
            } catch {
                bannerMessage = "Replacement failed: " + error.localizedDescription
            }
            isGeneratingTemplate = false
            generationTask = nil
        }
    }

    func regenerateTemplateStage(
        _ template: CustomPetTemplate,
        stageIndex: Int,
        quality: PetImageGenerationQuality? = nil,
        forceNewRequest: Bool = false
    ) {
        guard !isGeneratingTemplate,
              template.stages.indices.contains(stageIndex)
        else { return }
        let hasSavedRaw = templateStore.hasPendingReplacementRaw(
            templateID: template.id,
            stageIndex: stageIndex
        )
        let key: String?
        if hasSavedRaw && !forceNewRequest {
            key = nil
        } else {
            guard let resolved = resolvedImageAPIKey(supplied: nil) else { return }
            key = resolved
        }
        isGeneratingTemplate = true
        generationCompleted = 0
        generationTotal = 1
        generationStageName = template.stages[stageIndex].name
        bannerMessage = "Regenerating " + template.stages[stageIndex].name + "…"
        generationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await lineageGenerator.regenerateStage(
                    templateID: template.id,
                    stageIndex: stageIndex,
                    quality: quality,
                    apiKey: key,
                    forceNewRequest: forceNewRequest
                )
                reloadCustomTemplates()
                generationCompleted = 1
                bannerMessage = "The stage was regenerated and replaced in place."
            } catch is CancellationError {
                bannerMessage = "Stage regeneration was cancelled."
            } catch {
                let recoveryMessage = templateStore.hasPendingReplacementRaw(
                    templateID: template.id,
                    stageIndex: stageIndex
                )
                    ? " The API image remains saved locally. You can retry processing for free or confirm a new request."
                    : ""
                bannerMessage = "Stage regeneration failed: " + error.localizedDescription + recoveryMessage
            }
            isGeneratingTemplate = false
            generationTask = nil
        }
    }

    func hasPendingTemplateStageRaw(
        _ template: CustomPetTemplate,
        stageIndex: Int
    ) -> Bool {
        templateStore.hasPendingReplacementRaw(
            templateID: template.id,
            stageIndex: stageIndex
        )
    }

    func simulate(_ activity: CodexActivity) {
        receiveCodexActivity(activity, at: Date(), force: true)
    }

    func setPetVisible(_ visible: Bool) {
        isPetVisible = visible
        NotificationCenter.default.post(
            name: .sidekinVisibilityChanged,
            object: NSNumber(value: visible)
        )
    }

    func installCodexHooks() {
        guard let bridge = locateBridgeExecutable() else {
            bannerMessage = "The Codex bridge component was not found. Use a packaged application build."
            return
        }

        do {
            try hooksInstaller.install(
                at: SidekinPaths.defaultCodexHooksURL(),
                bridgeExecutable: bridge
            )
            hooksInstalled = true
            bannerMessage = "Codex integration is installed. New tasks will update the desktop pet automatically."
        } catch {
            bannerMessage = "Installation failed: " + error.localizedDescription
        }
    }

    func uninstallCodexHooks() {
        do {
            try hooksInstaller.uninstall(at: SidekinPaths.defaultCodexHooksURL())
            hooksInstalled = false
            bannerMessage = "Sidekin's Codex hooks were removed. Other hooks were left unchanged."
        } catch {
            bannerMessage = "Removal failed: " + error.localizedDescription
        }
    }

    func refreshHooksStatus() {
        hooksInstalled = hooksInstaller.isInstalled(at: SidekinPaths.defaultCodexHooksURL())
        hasImageAPIKey = apiKeyStore.hasKey()
    }

    func revealLocalData() {
        let directory = SidekinPaths.applicationSupportDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    func resetPet() {
        pet = PetSnapshot()
        clearPreview()
        bannerMessage = "A new Star Sprout Egg has hatched."
        persist()
    }

    private func resolvedImageAPIKey(
        supplied rawKey: String?,
        required: Bool = true
    ) -> String? {
        let suppliedKey = rawKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let suppliedKey, !suppliedKey.isEmpty {
            do {
                try apiKeyStore.save(suppliedKey)
                hasImageAPIKey = true
            } catch {
                bannerMessage = error.localizedDescription
                return nil
            }
        }

        do {
            guard let storedKey = try apiKeyStore.read() else {
                if required {
                    bannerMessage = "Enter your own OpenAI API key first."
                }
                return nil
            }
            return storedKey
        } catch {
            bannerMessage = error.localizedDescription
            return nil
        }
    }

    private func reloadCustomTemplates() {
        do {
            customTemplates = try templateStore.loadAll()
        } catch {
            bannerMessage = "Could not refresh the template library: " + error.localizedDescription
        }
    }

    private func refreshGenerationJobs() {
        do {
            generationJobs = try generationJobStore.loadAll()
        } catch {
            bannerMessage = "Could not read the resumable generation-job list: " + error.localizedDescription
        }
    }

    private func receiveCodexActivity(
        _ activity: CodexActivity,
        at date: Date,
        eventID: String? = nil,
        force: Bool = false
    ) {
        if !force, let lastSignal {
            let matchingID = eventID != nil && eventID == lastSignal.eventID
            let matchingTime = abs(date.timeIntervalSince(lastSignal.date)) < 5
            let isDuplicate = lastSignal.activity == activity && (matchingID || matchingTime)
            if isDuplicate { return }
        }

        guard PetLifecycleEngine.apply(
            activity,
            to: &pet,
            at: date,
            eventID: eventID,
            deduplicate: !force
        ) else { return }

        lastSignal = (activity, date, eventID)
        if !preservesLaunchPreview { clearPreview() }

        switch activity {
        case .idle: bannerMessage = "Codex is idle."
        case .running: bannerMessage = "Sprout noticed that Codex started working."
        case .completed: bannerMessage = "Task complete. Sprout gained growth experience."
        case .failed: bannerMessage = "The task hit a problem. Sprout is ready to try again with you."
        }
        persist()
    }

    private func advanceClock() {
        let before = pet
        PetLifecycleEngine.advance(&pet)
        if pet != before { persist() }
    }

    private func persist() {
        do {
            try persistence.save(pet)
        } catch {
            bannerMessage = "Local save failed: " + error.localizedDescription
        }
    }

    private func locateBridgeExecutable() -> URL? {
        let fileManager = FileManager.default
        let bundleCandidate = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/SidekinBridge")
        let executableDirectory = URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent()
        let siblingCandidate = executableDirectory.appendingPathComponent("SidekinBridge")
        return [bundleCandidate, siblingCandidate].first {
            fileManager.isExecutableFile(atPath: $0.path)
        }
    }
}
