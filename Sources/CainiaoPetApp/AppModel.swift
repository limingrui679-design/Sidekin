import AppKit
import CainiaoPetCore
import CainiaoPetCreator
import Combine
import Foundation

extension Notification.Name {
    static let cainiaoPetVisibilityChanged = Notification.Name("CainiaoPetVisibilityChanged")
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
            self.bannerMessage = "旧存档无法读取，已使用安全的新存档。"
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
            return template.name + " · 第 " + String(index + 1)
                + "/" + String(template.stages.count) + " 阶段"
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
    var codexSessionsDescription: String { CainiaoPetPaths.defaultCodexSessionsURL().path }

    func perform(_ action: PetCareAction) {
        PetLifecycleEngine.perform(action, on: &pet)
        if !preservesLaunchPreview { clearPreview() }

        switch action {
        case .feed: bannerMessage = "芽芽吃饱了一点。"
        case .play: bannerMessage = "一起玩耍，心情上升。"
        case .sleepOrWake:
            bannerMessage = pet.isSleeping ? "芽芽进入睡眠，精力会恢复。" : "芽芽醒来了。"
        }
        persist()
    }

    func choose(theme: PetVisualTheme) {
        pet.wardrobe.theme = theme
        pet.wardrobe.customTemplateID = nil
        clearPreview()
        bannerMessage = "已启用内置模板「" + theme.displayName + "」。"
        persist()
    }

    func activate(template: CustomPetTemplate) {
        pet.wardrobe.customTemplateID = template.id
        pet.wardrobe.theme = template.fallbackTheme
        clearPreview()
        bannerMessage = "已启用自定义宠物「" + template.name + "」。"
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
            bannerMessage = "API Key 已安全存入 macOS 钥匙串。"
        } catch {
            bannerMessage = error.localizedDescription
        }
    }

    func removeImageAPIKey() {
        do {
            try apiKeyStore.remove()
            hasImageAPIKey = false
            bannerMessage = "API Key 已从 macOS 钥匙串移除。"
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
        generationStageName = request.stageNames.first ?? "准备中"
        bannerMessage = "正在创建 " + String(request.stageNames.count) + " 个成长阶段…"

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
                bannerMessage = "「" + template.name + "」已生成并启用，共 "
                    + String(template.stages.count) + " 个成长阶段。"
            } catch is CancellationError {
                refreshGenerationJobs()
                bannerMessage = "生成已暂停；已经完成的阶段保存在本机，可稍后继续。"
            } catch {
                refreshGenerationJobs()
                bannerMessage = Task.isCancelled
                    ? "生成已暂停；已经完成的阶段保存在本机，可稍后继续。"
                    : "生成失败：" + error.localizedDescription + "；已完成阶段仍保存在本机，可稍后继续。"
            }
            isGeneratingTemplate = false
            generationTask = nil
        }
    }

    func cancelTemplateGeneration() {
        generationTask?.cancel()
    }

    func resumeTemplateGeneration(job: PetGenerationJob, apiKey: String? = nil) {
        guard !isGeneratingTemplate,
              let key = resolvedImageAPIKey(supplied: apiKey)
        else { return }
        isGeneratingTemplate = true
        generationCompleted = job.completedCount
        generationTotal = job.stageNames.count
        generationStageName = job.stageNames.indices.contains(job.nextStageIndex)
            ? job.stageNames[job.nextStageIndex]
            : "正在整理模板"
        bannerMessage = "从第 " + String(min(job.stageNames.count, job.nextStageIndex + 1))
            + " 阶段继续，不会重复请求已经保存的阶段。"

        generationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let template = try await lineageGenerator.resume(
                    jobID: job.id,
                    apiKey: key
                ) { [weak self] completed, total, stageName in
                    self?.generationCompleted = completed
                    self?.generationTotal = total
                    self?.generationStageName = stageName
                    self?.refreshGenerationJobs()
                }
                reloadCustomTemplates()
                activate(template: template)
                bannerMessage = "「" + template.name + "」已续跑完成并启用。"
            } catch is CancellationError {
                refreshGenerationJobs()
                bannerMessage = "生成已暂停；已付费生成的阶段仍保存在本机。"
            } catch {
                refreshGenerationJobs()
                bannerMessage = Task.isCancelled
                    ? "生成已暂停；已付费生成的阶段仍保存在本机。"
                    : "继续生成失败：" + error.localizedDescription
            }
            isGeneratingTemplate = false
            generationTask = nil
        }
    }

    func restartGenerationJob(_ job: PetGenerationJob, fromStage stageIndex: Int) {
        do {
            _ = try generationJobStore.restart(jobID: job.id, fromStage: stageIndex)
            refreshGenerationJobs()
            bannerMessage = "已清除第 \(stageIndex + 1) 阶段及其后续结果，可重新生成。"
        } catch {
            bannerMessage = error.localizedDescription
        }
    }

    func discardGenerationJob(_ job: PetGenerationJob) {
        do {
            try generationJobStore.remove(id: job.id)
            refreshGenerationJobs()
            bannerMessage = "未完成的生成任务已删除。"
        } catch {
            bannerMessage = error.localizedDescription
        }
    }

    func renameTemplate(_ template: CustomPetTemplate, to name: String) {
        do {
            let updated = try templateStore.rename(id: template.id, to: name)
            reloadCustomTemplates()
            bannerMessage = "模板已重命名为「" + updated.name + "」。"
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
            bannerMessage = "自定义模板「" + template.name + "」已删除。"
        } catch {
            bannerMessage = error.localizedDescription
        }
    }

    func exportTemplate(_ template: CustomPetTemplate, to url: URL) {
        do {
            let data = try templateStore.exportPackage(id: template.id)
            try data.write(to: url, options: .atomic)
            bannerMessage = "模板已导出为 " + url.lastPathComponent + "。"
        } catch {
            bannerMessage = "导出失败：" + error.localizedDescription
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
            bannerMessage = "已导入并启用「" + template.name + "」。"
        } catch {
            bannerMessage = "导入失败：" + error.localizedDescription
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
            : "替换阶段"
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
                bannerMessage = "已用本地图片替换「" + template.stages[stageIndex].name + "」。"
            } catch {
                bannerMessage = "替换失败：" + error.localizedDescription
            }
            isGeneratingTemplate = false
            generationTask = nil
        }
    }

    func regenerateTemplateStage(
        _ template: CustomPetTemplate,
        stageIndex: Int,
        quality: PetImageGenerationQuality? = nil
    ) {
        guard !isGeneratingTemplate,
              let key = resolvedImageAPIKey(supplied: nil),
              template.stages.indices.contains(stageIndex)
        else { return }
        isGeneratingTemplate = true
        generationCompleted = 0
        generationTotal = 1
        generationStageName = template.stages[stageIndex].name
        bannerMessage = "正在重新生成「" + template.stages[stageIndex].name + "」…"
        generationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await lineageGenerator.regenerateStage(
                    templateID: template.id,
                    stageIndex: stageIndex,
                    quality: quality,
                    apiKey: key
                )
                reloadCustomTemplates()
                generationCompleted = 1
                bannerMessage = "阶段已重新生成并原位替换。"
            } catch is CancellationError {
                bannerMessage = "已取消阶段重新生成。"
            } catch {
                bannerMessage = "阶段重新生成失败：" + error.localizedDescription
            }
            isGeneratingTemplate = false
            generationTask = nil
        }
    }

    func simulate(_ activity: CodexActivity) {
        receiveCodexActivity(activity, at: Date(), force: true)
    }

    func setPetVisible(_ visible: Bool) {
        isPetVisible = visible
        NotificationCenter.default.post(
            name: .cainiaoPetVisibilityChanged,
            object: NSNumber(value: visible)
        )
    }

    func installCodexHooks() {
        guard let bridge = locateBridgeExecutable() else {
            bannerMessage = "未找到 Codex 桥接组件，请先使用正式构建的应用。"
            return
        }

        do {
            try hooksInstaller.install(
                at: CainiaoPetPaths.defaultCodexHooksURL(),
                bridgeExecutable: bridge
            )
            hooksInstalled = true
            bannerMessage = "Codex 联动已安装；新任务会自动触发桌宠状态。"
        } catch {
            bannerMessage = "安装失败：" + error.localizedDescription
        }
    }

    func uninstallCodexHooks() {
        do {
            try hooksInstaller.uninstall(at: CainiaoPetPaths.defaultCodexHooksURL())
            hooksInstalled = false
            bannerMessage = "已移除菜鸟宠物添加的 Codex Hooks，其他 Hooks 保持不变。"
        } catch {
            bannerMessage = "移除失败：" + error.localizedDescription
        }
    }

    func refreshHooksStatus() {
        hooksInstalled = hooksInstaller.isInstalled(at: CainiaoPetPaths.defaultCodexHooksURL())
        hasImageAPIKey = apiKeyStore.hasKey()
    }

    func revealLocalData() {
        let directory = CainiaoPetPaths.applicationSupportDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    func resetPet() {
        pet = PetSnapshot()
        clearPreview()
        bannerMessage = "已经重新孵化一颗星芽蛋。"
        persist()
    }

    private func resolvedImageAPIKey(supplied rawKey: String?) -> String? {
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
                bannerMessage = "请先输入安装用户自己的 OpenAI API Key。"
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
            bannerMessage = "模板库刷新失败：" + error.localizedDescription
        }
    }

    private func refreshGenerationJobs() {
        do {
            generationJobs = try generationJobStore.loadAll()
        } catch {
            bannerMessage = "生成任务恢复列表读取失败：" + error.localizedDescription
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
        case .idle: bannerMessage = "Codex 已空闲。"
        case .running: bannerMessage = "芽芽发现 Codex 开始工作了。"
        case .completed: bannerMessage = "任务完成，芽芽获得了成长经验。"
        case .failed: bannerMessage = "任务遇到问题，芽芽会陪你再试一次。"
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
            bannerMessage = "本地存档失败：" + error.localizedDescription
        }
    }

    private func locateBridgeExecutable() -> URL? {
        let fileManager = FileManager.default
        let bundleCandidate = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/CainiaoPetBridge")
        let executableDirectory = URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent()
        let siblingCandidate = executableDirectory.appendingPathComponent("CainiaoPetBridge")
        return [bundleCandidate, siblingCandidate].first {
            fileManager.isExecutableFile(atPath: $0.path)
        }
    }
}
