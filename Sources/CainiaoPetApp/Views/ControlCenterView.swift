import AppKit
import CainiaoPetCore
import CainiaoPetCreator
import SwiftUI
import UniformTypeIdentifiers

private enum ControlSection: String, CaseIterable, Identifiable {
    case care
    case workshop
    case evolution
    case codex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .care: "战备舱"
        case .workshop: "宠物工坊"
        case .evolution: "进化图鉴"
        case .codex: "任务联动"
        }
    }

    var symbol: String {
        switch self {
        case .care: "shield.fill"
        case .workshop: "wand.and.stars"
        case .evolution: "square.stack.3d.up.fill"
        case .codex: "terminal.fill"
        }
    }
}

struct ControlCenterView: View {
    @ObservedObject var model: AppModel
    @State private var section: ControlSection = .care
    @State private var showResetConfirmation = false

    init(model: AppModel) {
        self.model = model
        let requestedSection = CommandLine.arguments
            .first { $0.hasPrefix("--section=") }
            .map { String($0.dropFirst("--section=".count)) }
            .flatMap(ControlSection.init(rawValue:))
        _section = State(initialValue: requestedSection ?? .care)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            content
        }
        .background(AppPalette.windowBackground)
        .overlay(alignment: .top) {
            if let message = model.bannerMessage {
                banner(message)
                    .padding(.top, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.84), value: model.bannerMessage)
        .alert("重新孵化宠物？", isPresented: $showResetConfirmation) {
            Button("取消", role: .cancel) {}
            Button("重新孵化", role: .destructive) { model.resetPet() }
        } message: {
            Text("当前成长、互动次数和进化记录会被新的星芽蛋替换，并恢复为内置模板。自定义模板文件不会删除。")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                ZStack {
                    GamePanelShape(cut: 10)
                        .fill(LinearGradient(colors: [.cyan, .blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(GamePanelShape(cut: 10).stroke(Color.white.opacity(0.7), lineWidth: 1))
                    Image(systemName: "star.square.on.square.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 42, height: 42)
                .shadow(color: .mint.opacity(0.32), radius: 12)

                VStack(alignment: .leading, spacing: 2) {
                    Text("芽芽")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                    Text("CODEX 战术伙伴")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)

            VStack(spacing: 8) {
                ForEach(ControlSection.allCases) { item in
                    Button {
                        section = item
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.symbol)
                                .frame(width: 22)
                            Text(item.title)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                            Spacer()
                        }
                        .foregroundStyle(section == item ? Color.white : Color.primary.opacity(0.72))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(
                            section == item
                                ? AnyShapeStyle(LinearGradient(colors: [.cyan.opacity(0.88), .blue, .indigo], startPoint: .leading, endPoint: .trailing))
                                : AnyShapeStyle(Color.clear),
                            in: GamePanelShape(cut: 9)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                Label("本地存档 · 生成时联网", systemImage: "lock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)

                Button("重新孵化") {
                    showResetConfirmation = true
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red.opacity(0.8))
            }
            .padding(18)
        }
        .padding(.vertical, 22)
        .frame(width: 205)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.025, green: 0.055, blue: 0.11),
                    Color(red: 0.035, green: 0.035, blue: 0.09)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            topBar

            Group {
                switch section {
                case .care:
                    CareDashboard(model: model)
                case .workshop:
                    PetWorkshopDashboard(model: model)
                case .evolution:
                    EvolutionDashboard(model: model)
                case .codex:
                    CodexDashboard(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(section.title)
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                Text("\(model.activeFormName) · \(model.pet.experience) 成长经验")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Circle()
                    .fill(activityColor)
                    .frame(width: 8, height: 8)
                Text(model.pet.isSleeping ? "正在睡觉" : model.pet.codexActivity.displayName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08), in: Capsule())

            Button {
                model.setPetVisible(!model.isPetVisible)
            } label: {
                Label(model.isPetVisible ? "隐藏桌宠" : "显示桌宠", systemImage: model.isPetVisible ? "eye.slash" : "eye")
            }
            .buttonStyle(SoftButtonStyle())
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .background(Color.black.opacity(0.08))
    }

    private func banner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "pawprint.fill")
                .foregroundStyle(.mint)
            Text(message)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Button {
                model.bannerMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.bold())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.2), radius: 18, y: 8)
    }

    private var activityColor: Color {
        if model.pet.isSleeping { return .indigo }
        switch model.pet.codexActivity {
        case .idle: return Color.mint
        case .running: return Color.cyan
        case .completed: return Color.green
        case .failed: return Color.orange
        }
    }
}

private struct CareDashboard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 24) {
                petCard

                VStack(spacing: 18) {
                    statsCard
                    actionsCard
                    historyCard
                }
                .frame(maxWidth: .infinity)
            }
            .padding(28)
        }
    }

    private var petCard: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)

            PetAvatarView(
                stage: model.displayedStage,
                theme: model.activeTheme,
                customAssetURL: model.displayedAssetURL,
                activity: model.pet.codexActivity,
                isSleeping: model.pet.isSleeping,
                size: 330
            )
            .frame(width: 330, height: 330)

            VStack(spacing: 4) {
                Text(model.pet.name)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text(model.activeFormName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(model.activeTheme.accentColor)
                Text(model.displayedStageSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(width: 380)
        .frame(minHeight: 505)
        .background {
            ZStack {
                RadialGradient(
                    colors: [.cyan.opacity(0.22), .blue.opacity(0.09), .purple.opacity(0.08), .clear],
                    center: .center,
                    startRadius: 18,
                    endRadius: 300
                )
                ArenaGrid()
            }
            .clipShape(GamePanelShape(cut: 25))
        }
        .overlay(GamePanelShape(cut: 25).stroke(Color.cyan.opacity(0.22), lineWidth: 1.2))
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("核心状态")
                    .font(.headline.weight(.bold))
                Spacer()
                Text("综合 \(Int(model.pet.wellbeing))")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.mint)
            }

            StatBar(label: "饱腹", value: model.pet.stats.hunger, icon: "carrot.fill", color: .orange)
            StatBar(label: "心情", value: model.pet.stats.mood, icon: "face.smiling.fill", color: .pink)
            StatBar(label: "精力", value: model.pet.stats.energy, icon: "bolt.fill", color: .cyan)

            Divider().overlay(Color.white.opacity(0.1))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(model.activeNextStageThreshold == nil ? "成长完成" : "下一阶段")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    if let threshold = model.activeNextStageThreshold {
                        Text("\(model.pet.experience) / \(threshold) XP")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else {
                        Text("最终形态")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ProgressView(value: model.activeStageProgress)
                    .tint(.mint)
            }
        }
        .cardStyle()
    }

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("互动指令")
                .font(.headline.weight(.bold))

            HStack(spacing: 12) {
                CareActionButton(title: "喂食", subtitle: "+饱腹", symbol: "carrot.fill", color: .orange) {
                    model.perform(.feed)
                }
                CareActionButton(title: "玩耍", subtitle: "+心情", symbol: "tennisball.fill", color: .pink) {
                    model.perform(.play)
                }
                CareActionButton(
                    title: model.pet.isSleeping ? "唤醒" : "睡觉",
                    subtitle: model.pet.isSleeping ? "继续陪伴" : "+精力",
                    symbol: model.pet.isSleeping ? "sun.max.fill" : "moon.stars.fill",
                    color: .indigo
                ) {
                    model.perform(.sleepOrWake)
                }
            }
        }
        .cardStyle()
    }

    private var historyCard: some View {
        HStack(spacing: 20) {
            MiniMetric(value: model.pet.feedCount, label: "喂食", symbol: "carrot.fill")
            MiniMetric(value: model.pet.playCount, label: "玩耍", symbol: "gamecontroller.fill")
            MiniMetric(value: model.pet.completedTasks, label: "完成任务", symbol: "checkmark.seal.fill")
            MiniMetric(value: model.pet.failedTasks, label: "共同重试", symbol: "arrow.clockwise")
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }
}

private struct StageTemplateAction: Identifiable {
    let id = UUID()
    let template: CustomPetTemplate
    let stageIndex: Int
}

private struct GenerationJobStageAction: Identifiable {
    let id = UUID()
    let job: PetGenerationJob
    let stageIndex: Int
}

private struct PetWorkshopDashboard: View {
    @ObservedObject var model: AppModel

    @State private var templateName = "我的新伙伴"
    @State private var concept = ""
    @State private var artDirection = "竞技游戏级 3D 角色建模，清晰轮廓，精致材质"
    @State private var mode: PetTemplateGenerationMode = .text
    @State private var quality: PetImageGenerationQuality = .medium
    @State private var stageCount = 5
    @State private var stageNames = CustomGrowthStagePlan.defaultNames(count: 5)
    @State private var referenceData: Data?
    @State private var referenceImage: NSImage?
    @State private var referenceFileName = ""
    @State private var apiKey = ""
    @State private var showGenerationConfirmation = false
    @State private var pendingRenameTemplate: CustomPetTemplate?
    @State private var renameText = ""
    @State private var showRenameAlert = false
    @State private var pendingDeleteTemplate: CustomPetTemplate?
    @State private var showDeleteAlert = false
    @State private var pendingDiscardJob: PetGenerationJob?
    @State private var showDiscardJobAlert = false
    @State private var pendingRestartJobStage: GenerationJobStageAction?
    @State private var showRestartJobAlert = false
    @State private var pendingRegeneration: StageTemplateAction?
    @State private var showRegenerationAlert = false

    private let artPresets = [
        "竞技游戏级 3D 角色建模，清晰轮廓，精致材质",
        "高级二次元赛璐璐，锐利形状，强对比配色",
        "软陶手办质感，圆润可爱，柔和棚拍光",
        "东方奇幻水墨，游戏角色立绘质感",
        "低多边形机甲，模块化结构，硬表面材质"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 18) {
                    livePreview
                    templateLibrary
                }
                if !model.generationJobs.isEmpty {
                    generationRecoveryPanel
                }
                creatorForm
                privacyPanel
            }
            .padding(28)
        }
        .onDisappear { model.clearPreview() }
        .alert("确认生成整条成长线？", isPresented: $showGenerationConfirmation) {
            Button("取消", role: .cancel) {}
            Button("生成 \(stageCount) 个阶段") {
                model.beginTemplateGeneration(request: generationRequest, apiKey: apiKey)
                apiKey = ""
            }
        } message: {
            Text("这会使用安装用户自己的 API Key，向 OpenAI 图像 API 发起约 \(stageCount) 次请求。按当前公开输出价格估算约 \(estimatedOutputCost)，另计文字与参考图输入；最终账单以 OpenAI 为准。每阶段完成后会立即保存在本机，可断点续跑。")
        }
        .alert("重命名模板", isPresented: $showRenameAlert) {
            TextField("模板名称", text: $renameText)
            Button("取消", role: .cancel) { pendingRenameTemplate = nil }
            Button("保存") {
                if let template = pendingRenameTemplate {
                    model.renameTemplate(template, to: renameText)
                }
                pendingRenameTemplate = nil
            }
        }
        .alert("删除这个模板？", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) { pendingDeleteTemplate = nil }
            Button("删除", role: .destructive) {
                if let template = pendingDeleteTemplate { model.deleteTemplate(template) }
                pendingDeleteTemplate = nil
            }
        } message: {
            Text("模板清单和所有阶段图片都会从本机删除，此操作不能在应用内撤销。")
        }
        .alert("删除未完成任务？", isPresented: $showDiscardJobAlert) {
            Button("取消", role: .cancel) { pendingDiscardJob = nil }
            Button("删除任务", role: .destructive) {
                if let job = pendingDiscardJob { model.discardGenerationJob(job) }
                pendingDiscardJob = nil
            }
        } message: {
            Text("已生成但尚未安装的阶段图片也会被删除。")
        }
        .alert("清除阶段恢复点？", isPresented: $showRestartJobAlert) {
            Button("取消", role: .cancel) { pendingRestartJobStage = nil }
            Button("清除并允许重新请求", role: .destructive) {
                if let action = pendingRestartJobStage {
                    model.restartGenerationJob(action.job, fromStage: action.stageIndex)
                }
                pendingRestartJobStage = nil
            }
        } message: {
            if let action = pendingRestartJobStage {
                Text("会删除第 \(action.stageIndex + 1) 阶段及其后续恢复文件。之后点击继续时，这些阶段将重新调用 API 并由安装用户自己的账户付费。")
            }
        }
        .alert("重新生成这个阶段？", isPresented: $showRegenerationAlert) {
            Button("取消", role: .cancel) { pendingRegeneration = nil }
            if pendingRegenerationHasSavedRaw {
                Button("免费重试本机原图") {
                    if let action = pendingRegeneration {
                        model.regenerateTemplateStage(
                            action.template,
                            stageIndex: action.stageIndex,
                            quality: quality
                        )
                    }
                    pendingRegeneration = nil
                }
                Button("重新请求（会产生费用）") {
                    if let action = pendingRegeneration {
                        model.regenerateTemplateStage(
                            action.template,
                            stageIndex: action.stageIndex,
                            quality: quality,
                            forceNewRequest: true
                        )
                    }
                    pendingRegeneration = nil
                }
            } else {
                Button("付费生成并替换") {
                    if let action = pendingRegeneration {
                        model.regenerateTemplateStage(
                            action.template,
                            stageIndex: action.stageIndex,
                            quality: quality
                        )
                    }
                    pendingRegeneration = nil
                }
            }
        } message: {
            if pendingRegenerationHasSavedRaw {
                Text("检测到上次已经付费返回并保存在本机的 API 原图。免费重试不会请求 API；只有选择重新请求才会产生新的费用，\(quality.displayName)质量输出约 \(singleImageOutputCost)，另计输入费用。")
            } else {
                Text("只会生成并替换所选阶段。\(quality.displayName)质量的 1024×1024 输出约 \(singleImageOutputCost)，另计输入费用；费用由安装用户自己的 API 账户承担。")
            }
        }
    }

    private var livePreview: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("当前伙伴")
                        .font(.headline.bold())
                    Text(model.activeCustomTemplate == nil ? "内置离线模板" : "本地自定义模板")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: model.activeCustomTemplate == nil ? "shippingbox.fill" : "wand.and.stars")
                    .foregroundStyle(model.activeTheme.accentColor)
            }

            PetAvatarView(
                stage: model.displayedStage,
                theme: model.activeTheme,
                customAssetURL: model.displayedAssetURL,
                activity: model.pet.codexActivity,
                isSleeping: model.pet.isSleeping,
                size: 235
            )
            .frame(width: 245, height: 245)

            Text(model.displayedFormName)
                .font(.system(size: 17, weight: .bold, design: .rounded))
            Text(model.displayedStageSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 280)
        .cardStyle()
    }

    private var templateLibrary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("模板库")
                        .font(.headline.bold())
                    Text("10 套离线模板始终可用；生成后的模板会出现在这里。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    Text("\(model.customTemplates.count) 个自定义")
                        .font(.caption2.bold())
                        .foregroundStyle(.mint)
                    Button {
                        importTemplatePackage()
                    } label: {
                        Label("导入模板", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.plain)
                    .font(.caption2.bold())
                }
            }

            FixedGrid(items: PetVisualTheme.allCases, columns: 5, spacing: 8) { theme in
                ThemeChoiceButton(
                    theme: theme,
                    stage: model.pet.stage,
                    isSelected: model.activeCustomTemplate == nil && model.activeTheme == theme
                ) {
                    model.choose(theme: theme)
                }
            }

            if !model.customTemplates.isEmpty {
                Divider().overlay(Color.white.opacity(0.1))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(model.customTemplates) { template in
                            CustomTemplateChoiceButton(
                                template: template,
                                assetURL: template.stages.first.flatMap {
                                    PetTemplateStore().assetURL(
                                        templateID: template.id,
                                        fileName: $0.assetFileName
                                    )
                                },
                                isSelected: model.activeCustomTemplate?.id == template.id,
                                renameAction: {
                                    pendingRenameTemplate = template
                                    renameText = template.name
                                    showRenameAlert = true
                                },
                                exportAction: { exportTemplatePackage(template) },
                                deleteAction: {
                                    pendingDeleteTemplate = template
                                    showDeleteAlert = true
                                },
                                regenerateStageAction: { index in
                                    pendingRegeneration = StageTemplateAction(
                                        template: template,
                                        stageIndex: index
                                    )
                                    showRegenerationAlert = true
                                },
                                replaceStageAction: { index in
                                    chooseReplacementImage(template: template, stageIndex: index)
                                }
                            ) {
                                model.activate(template: template)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private var generationRecoveryPanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("可继续的生成任务")
                        .font(.headline.bold())
                    Text("每次 API 返回后先保存原图，再完成抠图；重开应用也不会重复请求已保存阶段。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label("本机恢复点", systemImage: "externaldrive.fill.badge.checkmark")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            }

            ForEach(model.generationJobs) { job in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(job.templateName)
                                .font(.subheadline.bold())
                            Text("\(job.completedCount) / \(job.stageNames.count) 阶段 · \(job.state.displayName) · \(job.quality.displayName)质量")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if hasSavedCurrentRaw(job) {
                            Button("仅免费处理本机原图") {
                                model.resumeTemplateGeneration(
                                    job: job,
                                    allowNewRequests: false
                                )
                            }
                            .buttonStyle(SoftButtonStyle())
                            .disabled(model.isGeneratingTemplate)

                            Button("继续生成（可能付费）") {
                                model.resumeTemplateGeneration(job: job, apiKey: apiKey)
                                apiKey = ""
                            }
                            .buttonStyle(AccentButtonStyle(color: .orange))
                            .disabled(model.isGeneratingTemplate)
                        } else {
                            Button("继续 / 重试当前阶段") {
                                model.resumeTemplateGeneration(job: job, apiKey: apiKey)
                                apiKey = ""
                            }
                            .buttonStyle(AccentButtonStyle(color: .orange))
                            .disabled(model.isGeneratingTemplate)
                        }

                        Menu {
                            if hasSavedCurrentRaw(job), job.nextStageIndex < job.stageNames.count {
                                Button("清除当前原图并重新请求", systemImage: "arrow.counterclockwise") {
                                    confirmRestart(job, fromStage: job.nextStageIndex)
                                }
                                Divider()
                            }
                            if !job.completedStages.isEmpty {
                                Menu("从已完成阶段重做") {
                                    ForEach(job.completedStages) { stage in
                                        Button("第 \(stage.index + 1) 阶段 · \(stage.name)") {
                                            confirmRestart(job, fromStage: stage.index)
                                        }
                                    }
                                }
                            }
                            Button("删除任务", role: .destructive) {
                                pendingDiscardJob = job
                                showDiscardJobAlert = true
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .frame(width: 28)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 9) {
                            ForEach(job.stageNames.indices, id: \.self) { index in
                                RecoveryStagePreview(
                                    index: index,
                                    stageCount: job.stageNames.count,
                                    stageName: job.stageNames[index],
                                    theme: job.fallbackTheme,
                                    rawURL: model.generationRawPreviewURL(
                                        jobID: job.id,
                                        stageIndex: index
                                    ),
                                    processedURL: model.generationPreviewURL(
                                        jobID: job.id,
                                        stageIndex: index
                                    )
                                )
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    if let lastError = job.lastError, !lastError.isEmpty {
                        Text(lastError)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .lineLimit(2)
                    } else {
                        Text("每个阶段同时显示 API 原图和边缘连通抠图结果，可在继续前对照检查。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(Color.orange.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.18)))
            }
        }
        .cardStyle()
    }

    private var creatorForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("创建自定义成长模板")
                        .font(.title3.bold())
                    Text("用文字原创，或上传一张图后改画风 / 高相似延展。每个阶段都会生成独立姿态与轮廓。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label("1–8 阶段", systemImage: "square.stack.3d.up.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.cyan)
            }

            Picker("生成方式", selection: $mode) {
                ForEach(PetTemplateGenerationMode.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) { _, newMode in
                if concept.isEmpty, newMode.requiresReferenceImage {
                    concept = newMode == .faithful
                        ? "保留参考图主体的关键外观与辨识度，延展成完整成长线"
                        : "保留参考图主体物种特征，用新画风重新设计完整成长线"
                }
            }

            HStack(alignment: .center, spacing: 14) {
                Picker("质量", selection: $quality) {
                    ForEach(PetImageGenerationQuality.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 330)

                VStack(alignment: .leading, spacing: 2) {
                    Text(quality.detail)
                        .font(.caption.bold())
                    Text("\(stageCount) 阶段输出约 \(estimatedOutputCost)；不含文字及参考图输入费用")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent("模板名称") {
                        TextField("例如：月蚀小兽", text: $templateName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 270)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("宠物描述")
                            .font(.caption.bold())
                        TextEditor(text: $concept)
                            .font(.system(size: 13))
                            .scrollContentBackground(.hidden)
                            .padding(7)
                            .frame(minHeight: 92)
                            .background(Color.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1)))
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text("画风")
                            .font(.caption.bold())
                        TextField("输入任意画风描述", text: $artDirection)
                            .textFieldStyle(.roundedBorder)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(artPresets, id: \.self) { preset in
                                    Button(shortPresetName(preset)) { artDirection = preset }
                                        .buttonStyle(SoftButtonStyle())
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                if mode.requiresReferenceImage {
                    referencePicker
                        .frame(width: 230)
                }
            }

            Divider().overlay(Color.white.opacity(0.1))

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Stepper("成长阶段：\(stageCount)", value: $stageCount, in: 1...8)
                        .font(.subheadline.bold())
                        .onChange(of: stageCount) { _, newCount in
                            resizeStageNames(to: newCount)
                        }

                    FixedGrid(items: Array(stageNames.indices), columns: 4, spacing: 8) { index in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(index + 1) · \(CustomGrowthStagePlan.thresholds(count: stageCount)[index]) XP")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            TextField("阶段名", text: stageNameBinding(index))
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("OpenAI API Key")
                            .font(.caption.bold())
                        Spacer()
                        Label(model.hasImageAPIKey ? "已存钥匙串" : "尚未保存", systemImage: model.hasImageAPIKey ? "checkmark.shield.fill" : "key.fill")
                            .font(.caption2.bold())
                            .foregroundStyle(model.hasImageAPIKey ? .green : .orange)
                    }
                    SecureField(model.hasImageAPIKey ? "留空即可使用此用户已保存的 Key" : "安装用户自己的 sk-…", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("保存 Key") {
                            model.saveImageAPIKey(apiKey)
                            apiKey = ""
                        }
                        .buttonStyle(SoftButtonStyle())
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if model.hasImageAPIKey {
                            Button("移除") { model.removeImageAPIKey() }
                                .buttonStyle(.plain)
                                .foregroundStyle(.red.opacity(0.85))
                        }
                    }
                }
                .frame(width: 260)
            }

            if model.isGeneratingTemplate {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("正在生成：\(model.generationStageName)")
                            .font(.caption.bold())
                        Spacer()
                        Text("\(model.generationCompleted) / \(model.generationTotal)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(
                        value: Double(model.generationCompleted),
                        total: Double(max(1, model.generationTotal))
                    )
                    .tint(.cyan)
                    Button("取消生成") { model.cancelTemplateGeneration() }
                        .buttonStyle(SoftButtonStyle())
                }
            } else {
                HStack {
                    Text("生成前会再次确认；约 \(stageCount) 次请求，输出约 \(estimatedOutputCost)，费用由安装用户自己的 OpenAI API 账户承担。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        showGenerationConfirmation = true
                    } label: {
                        Label("生成整条成长线", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(AccentButtonStyle(color: .cyan))
                    .disabled(!canGenerate)
                    .opacity(canGenerate ? 1 : 0.45)
                }
            }
        }
        .cardStyle()
    }

    private var referencePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(mode == .faithful ? "高相似参考图" : "画风重制参考图")
                .font(.caption.bold())
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.28))
                if let referenceImage {
                    Image(nsImage: referenceImage)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 28))
                        Text("PNG、JPEG、HEIC 或 WebP")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 145)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1)))
            Text(referenceFileName.isEmpty ? "尚未选择图片" : referenceFileName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Button(referenceData == nil ? "选择参考图" : "更换参考图") {
                chooseReferenceImage()
            }
            .buttonStyle(SoftButtonStyle())
        }
    }

    private var privacyPanel: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.title3)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 4) {
                Text("隐私边界")
                    .font(.subheadline.bold())
                Text("成长存档、生成后的阶段图、模板清单都只保存在本机；API Key 存入 macOS 钥匙串。只有点击生成后，描述、你选择的参考图以及同一轮已生成的阶段图才会发送到 OpenAI 图像 API，以保持成长线一致。应用不会上传 Codex 对话、代码或任务内容。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .cardStyle()
    }

    private var canGenerate: Bool {
        !templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !concept.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !artDirection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!mode.requiresReferenceImage || referenceData != nil)
            && (model.hasImageAPIKey || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var estimatedOutputCost: String {
        String(format: "$%.3f", quality.estimatedOutputUSD(stageCount: stageCount))
    }

    private var singleImageOutputCost: String {
        String(format: "$%.3f", quality.estimatedOutputUSDPerSquareImage)
    }

    private var pendingRegenerationHasSavedRaw: Bool {
        guard let action = pendingRegeneration else { return false }
        return model.hasPendingTemplateStageRaw(
            action.template,
            stageIndex: action.stageIndex
        )
    }

    private func hasSavedCurrentRaw(_ job: PetGenerationJob) -> Bool {
        guard job.nextStageIndex < job.stageNames.count else { return false }
        return model.generationRawPreviewURL(
            jobID: job.id,
            stageIndex: job.nextStageIndex
        ) != nil
    }

    private func confirmRestart(_ job: PetGenerationJob, fromStage stageIndex: Int) {
        pendingRestartJobStage = GenerationJobStageAction(
            job: job,
            stageIndex: stageIndex
        )
        showRestartJobAlert = true
    }

    private var generationRequest: PetGenerationRequest {
        PetGenerationRequest(
            templateName: templateName,
            description: concept,
            artDirection: artDirection,
            mode: mode,
            quality: quality,
            stageNames: stageNames,
            referenceImage: mode.requiresReferenceImage ? referenceData : nil,
            fallbackTheme: model.activeTheme
        )
    }

    private func stageNameBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { stageNames.indices.contains(index) ? stageNames[index] : "" },
            set: { value in
                guard stageNames.indices.contains(index) else { return }
                stageNames[index] = value
            }
        )
    }

    private func resizeStageNames(to count: Int) {
        let previousNames = stageNames
        let previousDefaults = CustomGrowthStagePlan.defaultNames(count: previousNames.count)
        let defaults = CustomGrowthStagePlan.defaultNames(count: count)
        var updated = defaults
        for index in 0..<min(previousNames.count, updated.count) {
            if previousNames[index] != previousDefaults[index] {
                updated[index] = previousNames[index]
            }
        }
        stageNames = updated
    }

    private func shortPresetName(_ preset: String) -> String {
        String(preset.split(separator: "，").first ?? Substring(preset))
    }

    private func importTemplatePackage() {
        let panel = NSOpenPanel()
        panel.title = "导入 CainiaoPet 模板"
        panel.prompt = "导入"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "cainiaopet") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.importTemplate(from: url)
    }

    private func exportTemplatePackage(_ template: CustomPetTemplate) {
        let panel = NSSavePanel()
        panel.title = "导出 CainiaoPet 模板"
        panel.prompt = "导出"
        panel.allowedContentTypes = [UTType(filenameExtension: "cainiaopet") ?? .data]
        panel.nameFieldStringValue = template.name + ".cainiaopet"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.exportTemplate(template, to: url)
    }

    private func chooseReplacementImage(
        template: CustomPetTemplate,
        stageIndex: Int
    ) {
        let panel = NSOpenPanel()
        panel.title = "选择新的阶段图片"
        panel.prompt = "抠图并替换"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .heic, .webP]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard fileSize <= 25 * 1_024 * 1_024,
              let data = try? Data(contentsOf: url)
        else {
            model.bannerMessage = "图片无法读取或超过 25 MB。"
            return
        }
        model.replaceTemplateStage(template, stageIndex: stageIndex, with: data)
    }

    private func chooseReferenceImage() {
        let panel = NSOpenPanel()
        panel.title = "选择宠物参考图"
        panel.prompt = "使用这张图"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .heic, .webP]
        guard panel.runModal() == .OK,
              let url = panel.url
        else { return }
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard fileSize <= 25 * 1_024 * 1_024 else {
            model.bannerMessage = "参考图超过 25 MB，请先压缩后再选择。"
            return
        }
        guard
              let data = try? Data(contentsOf: url),
              let image = NSImage(data: data)
        else {
            model.bannerMessage = "无法读取这张图片，请换用 PNG、JPEG、HEIC 或 WebP。"
            return
        }
        referenceData = data
        referenceImage = image
        referenceFileName = url.lastPathComponent
    }
}

private struct RecoveryStagePreview: View {
    let index: Int
    let stageCount: Int
    let stageName: String
    let theme: PetVisualTheme
    let rawURL: URL?
    let processedURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                preview(url: rawURL, label: "原图")
                preview(url: processedURL, label: "抠图")
            }
            Text("\(index + 1) · \(stageName)")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(6)
        .background(Color.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
    }

    @ViewBuilder
    private func preview(url: URL?, label: String) -> some View {
        VStack(spacing: 2) {
            if let url {
                PetAvatarView(
                    stage: CustomGrowthStagePlan.canonicalStage(
                        customIndex: index,
                        stageCount: stageCount
                    ),
                    theme: theme,
                    customAssetURL: url,
                    activity: .idle,
                    isSleeping: false,
                    size: 54,
                    isAnimated: false
                )
                .frame(width: 58, height: 52)
                .background(Color.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 7))
            } else {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .foregroundStyle(Color.white.opacity(0.15))
                    .frame(width: 58, height: 52)
                    .overlay(Image(systemName: "hourglass").foregroundStyle(.secondary))
            }
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct FixedGrid<Item, Cell: View>: View {
    let items: [Item]
    let columns: Int
    let spacing: CGFloat
    @ViewBuilder let cell: (Item) -> Cell

    private var rowStarts: [Int] {
        guard columns > 0 else { return [] }
        return Array(stride(from: 0, to: items.count, by: columns))
    }

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(rowStarts, id: \.self) { rowStart in
                HStack(spacing: spacing) {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = rowStart + column
                        if index < items.count {
                            cell(items[index])
                                .frame(minWidth: 0, maxWidth: .infinity)
                        } else {
                            Color.clear
                                .frame(minWidth: 0, maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }
}

private struct EvolutionDashboard: View {
    @ObservedObject var model: AppModel

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.activeCustomTemplate.map { "\($0.stages.count) 阶段自定义成长线" } ?? "五阶段独立物种进化")
                            .font(.title2.bold())
                        Text("点击任一模型可在浮动桌宠中临时预览，不会改动成长存档。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.hasActivePreview {
                        Button("结束预览") { model.clearPreview() }
                            .buttonStyle(SoftButtonStyle())
                    }
                }

                LazyVGrid(columns: columns, spacing: 16) {
                    if let template = model.activeCustomTemplate {
                        ForEach(template.stages) { customStage in
                            let stage = CustomGrowthStagePlan.canonicalStage(
                                customIndex: customStage.index,
                                stageCount: template.stages.count
                            )
                            EvolutionCard(
                                stage: stage,
                                name: customStage.name,
                                phaseLabel: "第 \(customStage.index + 1) / \(template.stages.count) 阶段",
                                subtitle: customStage.experienceThreshold == 0
                                    ? "初始形态"
                                    : "达到 \(customStage.experienceThreshold) XP 解锁",
                                theme: template.fallbackTheme,
                                assetURL: PetTemplateStore().assetURL(
                                    templateID: template.id,
                                    fileName: customStage.assetFileName
                                ),
                                isCurrent: model.activeCustomStageIndex == customStage.index,
                                isPreviewing: model.previewCustomStageIndex == customStage.index
                            ) {
                                model.setPreview(customStageIndex: customStage.index)
                            }
                        }
                    } else {
                        ForEach(PetStage.allCases) { stage in
                            EvolutionCard(
                                stage: stage,
                                name: model.activeTheme.formName(at: stage),
                                phaseLabel: stage.displayName,
                                subtitle: stage.subtitle,
                                theme: model.activeTheme,
                                assetURL: nil,
                                isCurrent: model.pet.stage == stage,
                                isPreviewing: model.previewStage == stage
                            ) {
                                model.setPreview(stage: stage)
                            }
                        }
                    }
                }

                if let template = model.activeCustomTemplate {
                    CustomLineagePanel(template: template)
                } else {
                    LineageAnchorPanel(theme: model.activeTheme)
                }
            }
            .padding(28)
        }
        .onDisappear { model.clearPreview() }
    }
}

private struct CodexDashboard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.black.opacity(0.65))
                                Image(systemName: "terminal.fill")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(.mint)
                            }
                            .frame(width: 52, height: 52)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Codex 状态监听")
                                    .font(.headline.bold())
                                Label("本地监听已运行", systemImage: "checkmark.circle.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.green)
                            }
                        }

                        Text("应用只读取任务生命周期事件：运行、完成和失败；不会保存提示词、代码、工具输出或对话内容。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("当前状态")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(model.pet.codexActivity.displayName)
                            .font(.system(size: 23, weight: .bold, design: .rounded))
                        HStack(spacing: 8) {
                            Circle().fill(statusColor).frame(width: 9, height: 9)
                            Text(model.hooksInstalled ? "官方 Hooks 已安装" : "只读监听模式")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .frame(width: 230, alignment: .leading)
                    .cardStyle()
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("官方 Hooks 桥接")
                                .font(.headline.bold())
                            Text("安装后，Codex 提交任务与结束任务时会直接通知芽芽；现有 Hooks 会被保留。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.hooksInstalled {
                            Button("移除联动") { model.uninstallCodexHooks() }
                                .buttonStyle(SoftButtonStyle())
                        } else {
                            Button("安装 Codex 联动") { model.installCodexHooks() }
                                .buttonStyle(AccentButtonStyle(color: .mint))
                        }
                    }
                }
                .cardStyle()

                VStack(alignment: .leading, spacing: 14) {
                    Text("状态响应测试")
                        .font(.headline.bold())
                    Text("不用真正运行任务，也可以检查三种动画和成长反馈。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        SimulationButton(title: "运行", symbol: "ellipsis", color: .cyan) {
                            model.simulate(.running)
                        }
                        SimulationButton(title: "完成", symbol: "checkmark", color: .green) {
                            model.simulate(.completed)
                        }
                        SimulationButton(title: "失败", symbol: "exclamationmark", color: .orange) {
                            model.simulate(.failed)
                        }
                        SimulationButton(title: "空闲", symbol: "pause", color: .mint) {
                            model.simulate(.idle)
                        }
                    }
                }
                .cardStyle()

                VStack(alignment: .leading, spacing: 12) {
                    Label("本地数据与隐私", systemImage: "lock.shield.fill")
                        .font(.headline.bold())

                    PathRow(label: "成长存档", value: model.storageDescription)
                    PathRow(label: "自定义模板", value: model.templatesDescription)
                    PathRow(label: "Codex 会话目录", value: model.codexSessionsDescription)

                    HStack {
                        Text("日常养成与 Codex 联动完全本地；只有你确认生成模板后，描述、参考图和同一轮阶段锚点才会发往 OpenAI 图像 API。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("打开本地数据文件夹") { model.revealLocalData() }
                            .buttonStyle(SoftButtonStyle())
                    }
                }
                .cardStyle()
            }
            .padding(28)
        }
        .onAppear { model.refreshHooksStatus() }
    }

    private var statusColor: Color {
        switch model.pet.codexActivity {
        case .idle: .mint
        case .running: .cyan
        case .completed: .green
        case .failed: .orange
        }
    }
}

private struct StatBar: View {
    let label: String
    let value: Double
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(color)
            Text(label)
                .font(.caption.weight(.semibold))
                .frame(width: 38, alignment: .leading)
            ProgressView(value: value, total: 100)
                .tint(color)
            Text("\(Int(value))")
                .font(.caption.monospacedDigit().weight(.bold))
                .frame(width: 28, alignment: .trailing)
        }
    }
}

private struct CareActionButton: View {
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(color.opacity(0.12), in: GamePanelShape(cut: 10))
            .overlay(GamePanelShape(cut: 10).stroke(color.opacity(0.42), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct MiniMetric: View {
    let value: Int
    let label: String
    let symbol: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).foregroundStyle(.mint)
            Text("\(value)")
                .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ThemeChoiceButton: View {
    let theme: PetVisualTheme
    let stage: PetStage
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    theme.previewBackground
                    ArenaGrid()
                        .opacity(0.42)
                    PetAvatarView(
                        stage: stage,
                        theme: theme,
                        customAssetURL: nil,
                        activity: .idle,
                        isSleeping: false,
                        size: 78,
                        isAnimated: false
                    )
                }
                .frame(height: 78)
                .clipShape(GamePanelShape(cut: 9))

                HStack(spacing: 4) {
                    Image(systemName: theme.symbolName)
                    Text(theme.displayName)
                        .lineLimit(1)
                        .minimumScaleFactor(0.88)
                }
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(isSelected ? theme.accentColor : .primary)

                Text(theme.speciesAnchor)
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
            .padding(7)
            .frame(maxWidth: .infinity)
            .background(
                isSelected ? theme.accentColor.opacity(0.13) : Color.white.opacity(0.04),
                in: GamePanelShape(cut: 10)
            )
            .overlay {
                GamePanelShape(cut: 10)
                    .stroke(
                        isSelected ? theme.accentColor.opacity(0.72) : Color.white.opacity(0.08),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(theme.accentColor)
                        .padding(8)
                    }
            }
            .clipped()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.displayName)，\(isSelected ? "已选择" : "点击选择")")
    }
}

private struct CustomTemplateChoiceButton: View {
    let template: CustomPetTemplate
    let assetURL: URL?
    let isSelected: Bool
    let renameAction: () -> Void
    let exportAction: () -> Void
    let deleteAction: () -> Void
    let regenerateStageAction: (Int) -> Void
    let replaceStageAction: (Int) -> Void
    let action: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Button(action: action) {
                VStack(spacing: 7) {
                    PetAvatarView(
                        stage: CustomGrowthStagePlan.canonicalStage(
                            customIndex: 0,
                            stageCount: template.stages.count
                        ),
                        theme: template.fallbackTheme,
                        customAssetURL: assetURL,
                        activity: .idle,
                        isSleeping: false,
                        size: 105,
                        isAnimated: false
                    )
                    .frame(width: 112, height: 94)

                    Text(template.name)
                        .font(.caption.bold())
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 4) {
                Text("\(template.stages.count) 阶段 · \(template.generationMode.displayName)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Menu {
                    Button("重命名", systemImage: "pencil", action: renameAction)
                    Button("导出模板", systemImage: "square.and.arrow.up", action: exportAction)
                    Menu("AI 重新生成阶段", systemImage: "arrow.triangle.2.circlepath") {
                        ForEach(template.stages.indices, id: \.self) { index in
                            Button("\(index + 1) · \(template.stages[index].name)") {
                                regenerateStageAction(index)
                            }
                        }
                    }
                    Menu("用本地图片替换", systemImage: "photo.badge.arrow.down") {
                        ForEach(template.stages.indices, id: \.self) { index in
                            Button("\(index + 1) · \(template.stages[index].name)") {
                                replaceStageAction(index)
                            }
                        }
                    }
                    Divider()
                    Button("删除模板", systemImage: "trash", role: .destructive, action: deleteAction)
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.system(size: 12))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)
            }
        }
        .padding(9)
        .frame(width: 155)
        .background(
            isSelected ? Color.mint.opacity(0.13) : Color.white.opacity(0.04),
            in: GamePanelShape(cut: 11)
        )
        .overlay(
            GamePanelShape(cut: 11)
                .stroke(isSelected ? Color.mint.opacity(0.7) : Color.white.opacity(0.08), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.mint)
                    .padding(8)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(template.name)，\(template.stages.count) 个阶段")
    }
}

private struct EvolutionCard: View {
    let stage: PetStage
    let name: String
    let phaseLabel: String
    let subtitle: String
    let theme: PetVisualTheme
    let assetURL: URL?
    let isCurrent: Bool
    let isPreviewing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                PetAvatarView(
                    stage: stage,
                    theme: theme,
                    customAssetURL: assetURL,
                    activity: .idle,
                    isSleeping: false,
                    size: 145
                )
                .frame(width: 145, height: 145)

                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(name)
                            .font(.headline.bold())
                        if isCurrent {
                            Text("当前")
                                .font(.caption2.bold())
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.mint.opacity(0.18), in: Capsule())
                                .foregroundStyle(.mint)
                        }
                    }
                    Text(phaseLabel)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(theme.accentColor)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                    Label(isPreviewing ? "正在预览" : "点击预览", systemImage: isPreviewing ? "eye.fill" : "eye")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isPreviewing ? .cyan : .secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(
                isPreviewing ? Color.cyan.opacity(0.12) : Color.white.opacity(0.055),
                in: GamePanelShape(cut: 16)
            )
            .overlay(
                GamePanelShape(cut: 16)
                    .stroke(isPreviewing ? Color.cyan.opacity(0.55) : Color.white.opacity(0.09), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct CustomLineagePanel: View {
    let template: CustomPetTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(template.fallbackTheme.accentColor)
                Text("\(template.name) · 模板信息")
                    .font(.headline.bold())
                Spacer()
                Text(template.generationMode.displayName)
                    .font(.caption2.bold())
                    .foregroundStyle(.mint)
            }

            HStack(alignment: .top, spacing: 18) {
                AnchorFact(symbol: "square.stack.3d.up.fill", label: "成长阶段", value: "\(template.stages.count) 个阶段")
                AnchorFact(symbol: "paintpalette.fill", label: "画风", value: template.artDirection)
                AnchorFact(symbol: "text.bubble.fill", label: "核心设定", value: template.basePrompt)
            }
        }
        .cardStyle()
    }
}

private struct LineageAnchorPanel: View {
    let theme: PetVisualTheme

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: theme.symbolName)
                    .foregroundStyle(theme.accentColor)
                Text("\(theme.displayName) · 造型锚点")
                    .font(.headline.bold())
                Spacer()
                Text("不是同模换色")
                    .font(.caption2.bold())
                    .foregroundStyle(theme.secondaryAccentColor)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                AnchorFact(symbol: "pawprint.fill", label: "物种", value: theme.speciesAnchor)
                AnchorFact(symbol: "figure.run", label: "运动", value: theme.motionAnchor)
                AnchorFact(symbol: "square.3.layers.3d", label: "轮廓", value: theme.silhouetteAnchor)
                AnchorFact(symbol: "sparkles", label: "材质 / 能量", value: "\(theme.materialAnchor) · \(theme.energyAnchor)")
            }
        }
        .cardStyle()
    }
}

private struct AnchorFact: View {
    let symbol: String
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SimulationButton: View {
    let title: String
    let symbol: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(color.opacity(0.12), in: GamePanelShape(cut: 9))
                .overlay(GamePanelShape(cut: 9).stroke(color.opacity(0.42), lineWidth: 1))
                .foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }
}

private struct PathRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.caption.weight(.semibold))
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}

private struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(configuration.isPressed ? 0.14 : 0.08), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

private struct AccentButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(Color.black.opacity(0.78))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(color.opacity(configuration.isPressed ? 0.72 : 0.95), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

private struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(
                LinearGradient(
                    colors: [Color.white.opacity(0.075), Color.blue.opacity(0.035), Color.black.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: GamePanelShape(cut: 15)
            )
            .overlay(GamePanelShape(cut: 15).stroke(Color.cyan.opacity(0.13), lineWidth: 1))
    }
}

private extension View {
    func cardStyle() -> some View {
        modifier(CardModifier())
    }
}

private enum AppPalette {
    static let windowBackground = LinearGradient(
        colors: [
            Color(red: 0.018, green: 0.035, blue: 0.08),
            Color(red: 0.03, green: 0.075, blue: 0.12),
            Color(red: 0.075, green: 0.035, blue: 0.12)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private struct GamePanelShape: Shape {
    let cut: CGFloat

    func path(in rect: CGRect) -> Path {
        let amount = min(cut, min(rect.width, rect.height) * 0.34)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + amount, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - amount, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + amount))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - amount))
        path.addLine(to: CGPoint(x: rect.maxX - amount, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + amount, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - amount))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + amount))
        path.closeSubpath()
        return path
    }
}

private struct ArenaGrid: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            let spacing: CGFloat = 34

            for x in stride(from: -size.height, through: size.width + size.height, by: spacing) {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x - size.height, y: size.height))
            }
            for x in stride(from: 0, through: size.width + size.height, by: spacing) {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x + size.height, y: size.height))
            }

            context.stroke(path, with: .color(.cyan.opacity(0.045)), lineWidth: 0.7)
        }
        .allowsHitTesting(false)
    }
}
