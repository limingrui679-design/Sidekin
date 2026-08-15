import AppKit
import SidekinCore
import SidekinCreator
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
        case .care: "Command Center"
        case .workshop: "Pet Workshop"
        case .evolution: "Evolution Codex"
        case .codex: "Codex Link"
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
        .alert("Hatch a New Pet?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Hatch Again", role: .destructive) { model.resetPet() }
        } message: {
            Text("Current growth, interaction counts, and evolution history will be replaced by a new Star Sprout Egg, and the built-in template will be restored. Custom template files will not be deleted.")
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
                    Text("CAINIAOPET")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                    Text("CODEX TACTICAL COMPANION")
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
                Label("LOCAL SAVE · ONLINE ONLY FOR GENERATION", systemImage: "lock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)

                Button("Hatch Again") {
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
                Text("\(model.activeFormName) · \(model.pet.experience) GROWTH XP")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Circle()
                    .fill(activityColor)
                    .frame(width: 8, height: 8)
                Text(model.pet.isSleeping ? "Sleeping" : model.pet.codexActivity.displayName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08), in: Capsule())

            Button {
                model.setPetVisible(!model.isPetVisible)
            } label: {
                Label(model.isPetVisible ? "Hide Desktop Pet" : "Show Desktop Pet", systemImage: model.isPetVisible ? "eye.slash" : "eye")
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
                Text("CORE STATUS")
                    .font(.headline.weight(.bold))
                Spacer()
                Text("Overall \(Int(model.pet.wellbeing))")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.mint)
            }

            StatBar(label: "Hunger", value: model.pet.stats.hunger, icon: "carrot.fill", color: .orange)
            StatBar(label: "Mood", value: model.pet.stats.mood, icon: "face.smiling.fill", color: .pink)
            StatBar(label: "Energy", value: model.pet.stats.energy, icon: "bolt.fill", color: .cyan)

            Divider().overlay(Color.white.opacity(0.1))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(model.activeNextStageThreshold == nil ? "Growth Complete" : "Next Stage")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    if let threshold = model.activeNextStageThreshold {
                        Text("\(model.pet.experience) / \(threshold) XP")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Final Form")
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
            Text("CARE COMMANDS")
                .font(.headline.weight(.bold))

            HStack(spacing: 12) {
                CareActionButton(title: "Feed", subtitle: "+Hunger", symbol: "carrot.fill", color: .orange) {
                    model.perform(.feed)
                }
                CareActionButton(title: "Play", subtitle: "+Mood", symbol: "tennisball.fill", color: .pink) {
                    model.perform(.play)
                }
                CareActionButton(
                    title: model.pet.isSleeping ? "Wake Up" : "Sleep",
                    subtitle: model.pet.isSleeping ? "Back to your side" : "+Energy",
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
            MiniMetric(value: model.pet.feedCount, label: "Fed", symbol: "carrot.fill")
            MiniMetric(value: model.pet.playCount, label: "Played", symbol: "gamecontroller.fill")
            MiniMetric(value: model.pet.completedTasks, label: "Completed", symbol: "checkmark.seal.fill")
            MiniMetric(value: model.pet.failedTasks, label: "Retried", symbol: "arrow.clockwise")
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

    @State private var templateName = "My New Companion"
    @State private var concept = ""
    @State private var artDirection = "Competitive-game 3D character art, readable silhouette, premium materials"
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
    @State private var themeSearch = ""
    @State private var selectedThemeCategory: PetThemeCategory?

    private let artPresets = [
        "Competitive-game 3D character art, readable silhouette, premium materials",
        "Premium anime cel shading, sharp shapes, high-contrast palette",
        "Soft clay figurine, rounded and charming, gentle studio lighting",
        "Eastern fantasy ink wash, polished game character illustration",
        "Low-poly mecha, modular construction, hard-surface materials"
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
        .alert("Generate the Full Growth Line?", isPresented: $showGenerationConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Generate \(stageCount) Stages") {
                model.beginTemplateGeneration(request: generationRequest, apiKey: apiKey)
                apiKey = ""
            }
        } message: {
            Text("This uses your own API key and sends about \(stageCount) requests to the OpenAI image API. Estimated output cost is \(estimatedOutputCost), excluding text and reference-image input. OpenAI's final bill is authoritative. Each completed stage is saved locally for resumable generation.")
        }
        .alert("Rename Template", isPresented: $showRenameAlert) {
            TextField("Template name", text: $renameText)
            Button("Cancel", role: .cancel) { pendingRenameTemplate = nil }
            Button("Save") {
                if let template = pendingRenameTemplate {
                    model.renameTemplate(template, to: renameText)
                }
                pendingRenameTemplate = nil
            }
        }
        .alert("Delete This Template?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { pendingDeleteTemplate = nil }
            Button("Delete", role: .destructive) {
                if let template = pendingDeleteTemplate { model.deleteTemplate(template) }
                pendingDeleteTemplate = nil
            }
        } message: {
            Text("The template manifest and every stage image will be deleted from this Mac. This cannot be undone in the app.")
        }
        .alert("Delete Unfinished Job?", isPresented: $showDiscardJobAlert) {
            Button("Cancel", role: .cancel) { pendingDiscardJob = nil }
            Button("Delete Job", role: .destructive) {
                if let job = pendingDiscardJob { model.discardGenerationJob(job) }
                pendingDiscardJob = nil
            }
        } message: {
            Text("Generated stage images that have not yet been installed will also be deleted.")
        }
        .alert("Clear Stage Recovery Data?", isPresented: $showRestartJobAlert) {
            Button("Cancel", role: .cancel) { pendingRestartJobStage = nil }
            Button("Clear and Allow New Requests", role: .destructive) {
                if let action = pendingRestartJobStage {
                    model.restartGenerationJob(action.job, fromStage: action.stageIndex)
                }
                pendingRestartJobStage = nil
            }
        } message: {
            if let action = pendingRestartJobStage {
                Text("This deletes recovery files for stage \(action.stageIndex + 1) and every later stage. Continuing afterward will request those stages again and charge your own API account.")
            }
        }
        .alert("Regenerate This Stage?", isPresented: $showRegenerationAlert) {
            Button("Cancel", role: .cancel) { pendingRegeneration = nil }
            if pendingRegenerationHasSavedRaw {
                Button("Retry Saved Image for Free") {
                    if let action = pendingRegeneration {
                        model.regenerateTemplateStage(
                            action.template,
                            stageIndex: action.stageIndex,
                            quality: quality
                        )
                    }
                    pendingRegeneration = nil
                }
                Button("Request Again (Paid)") {
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
                Button("Generate and Replace (Paid)") {
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
                Text("A previously paid API image is already saved locally. Retrying it does not call the API. Only Request Again creates a new charge: approximately \(singleImageOutputCost) for \(quality.displayName) output, excluding input cost.")
            } else {
                Text("Only the selected stage will be generated and replaced. A 1024×1024 \(quality.displayName) output is approximately \(singleImageOutputCost), excluding input cost. Your own API account is charged.")
            }
        }
    }

    private var livePreview: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CURRENT COMPANION")
                        .font(.headline.bold())
                    Text(model.activeCustomTemplate == nil ? "Built-in offline theme" : "Local custom template")
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
                    Text("TEMPLATE LIBRARY")
                        .font(.headline.bold())
                    Text("200 offline lineages: a balanced ten-category core plus a searchable tag-based expansion. Generated templates appear here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    Text("\(filteredThemes.count) SHOWN · \(model.customTemplates.count) CUSTOM")
                        .font(.caption2.bold())
                        .foregroundStyle(.mint)
                    Button {
                        importTemplatePackage()
                    } label: {
                        Label("Import Template", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.plain)
                    .font(.caption2.bold())
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search name, form, material, or concept", text: $themeSearch)
                    .textFieldStyle(.plain)
                if !themeSearch.isEmpty {
                    Button {
                        themeSearch = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.08), lineWidth: 1))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ThemeCategoryFilterButton(
                        title: "All 200",
                        symbol: "square.grid.3x3.fill",
                        isSelected: selectedThemeCategory == nil
                    ) {
                        selectedThemeCategory = nil
                    }

                    ForEach(PetThemeCategory.allCases) { category in
                        ThemeCategoryFilterButton(
                            title: category.displayName,
                            symbol: category.symbolName,
                            isSelected: selectedThemeCategory == category
                        ) {
                            selectedThemeCategory = category
                        }
                    }
                }
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 116, maximum: 152), spacing: 8)],
                spacing: 8
            ) {
                ForEach(filteredThemes) { theme in
                    ThemeChoiceButton(
                        theme: theme,
                        stage: model.pet.stage,
                        isSelected: model.activeCustomTemplate == nil && model.activeTheme == theme
                    ) {
                        model.choose(theme: theme)
                    }
                }
            }

            if filteredThemes.isEmpty {
                ContentUnavailableView(
                    "No Matching Theme",
                    systemImage: "magnifyingglass",
                    description: Text("Try another name, material, existence type, or clear the category filter.")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
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

    private var filteredThemes: [PetVisualTheme] {
        let query = themeSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return PetVisualTheme.allCases.filter { theme in
            let categoryMatches = selectedThemeCategory.map { theme.category == $0 } ?? true
            guard categoryMatches else { return false }
            guard !query.isEmpty else { return true }
            let searchable = [
                theme.displayName,
                theme.taxonomyLabel,
                theme.tags.joined(separator: " "),
                theme.subtitle,
                theme.lineageIntroduction,
                theme.existenceAnchor,
                theme.silhouetteAnchor,
                theme.motionAnchor,
                theme.materialAnchor,
                theme.energyAnchor
            ]
            return searchable.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var generationRecoveryPanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("RESUMABLE GENERATION JOBS")
                        .font(.headline.bold())
                    Text("Each API image is saved before cutout processing. Relaunching the app will not request saved stages again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label("LOCAL CHECKPOINT", systemImage: "externaldrive.fill.badge.checkmark")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            }

            ForEach(model.generationJobs) { job in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(job.templateName)
                                .font(.subheadline.bold())
                            Text("\(job.completedCount) / \(job.stageNames.count) STAGES · \(job.state.displayName) · \(job.quality.displayName)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if hasSavedCurrentRaw(job) {
                            Button("Process Saved Image Only (Free)") {
                                model.resumeTemplateGeneration(
                                    job: job,
                                    allowNewRequests: false
                                )
                            }
                            .buttonStyle(SoftButtonStyle())
                            .disabled(model.isGeneratingTemplate)

                            Button("Continue Generation (May Be Paid)") {
                                model.resumeTemplateGeneration(job: job, apiKey: apiKey)
                                apiKey = ""
                            }
                            .buttonStyle(AccentButtonStyle(color: .orange))
                            .disabled(model.isGeneratingTemplate)
                        } else {
                            Button("Continue / Retry Current Stage") {
                                model.resumeTemplateGeneration(job: job, apiKey: apiKey)
                                apiKey = ""
                            }
                            .buttonStyle(AccentButtonStyle(color: .orange))
                            .disabled(model.isGeneratingTemplate)
                        }

                        Menu {
                            if hasSavedCurrentRaw(job), job.nextStageIndex < job.stageNames.count {
                                Button("Clear Current Image and Request Again", systemImage: "arrow.counterclockwise") {
                                    confirmRestart(job, fromStage: job.nextStageIndex)
                                }
                                Divider()
                            }
                            if !job.completedStages.isEmpty {
                                Menu("Restart from a Completed Stage") {
                                    ForEach(job.completedStages) { stage in
                                        Button("Stage \(stage.index + 1) · \(stage.name)") {
                                            confirmRestart(job, fromStage: stage.index)
                                        }
                                    }
                                }
                            }
                            Button("Delete Job", role: .destructive) {
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
                        Text("Each stage shows the saved API image beside the edge-connected cutout for comparison before continuing.")
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
                    Text("CREATE A CUSTOM GROWTH TEMPLATE")
                        .font(.title3.bold())
                    Text("Create from text, restyle a reference, or extend it with high fidelity. Every stage receives a distinct pose and silhouette.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label("1–8 STAGES", systemImage: "square.stack.3d.up.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.cyan)
            }

            Picker("Generation Mode", selection: $mode) {
                ForEach(PetTemplateGenerationMode.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) { _, newMode in
                if concept.isEmpty, newMode.requiresReferenceImage {
                    concept = newMode == .faithful
                        ? "Preserve the reference subject's defining appearance and identity while extending it into a full growth line"
                        : "Keep the reference subject's species traits while redesigning the full growth line in a new art style"
                }
            }

            HStack(alignment: .center, spacing: 14) {
                Picker("Quality", selection: $quality) {
                    ForEach(PetImageGenerationQuality.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 330)

                VStack(alignment: .leading, spacing: 2) {
                    Text(quality.detail)
                        .font(.caption.bold())
                    Text("Estimated output for \(stageCount) stages: \(estimatedOutputCost), excluding text and reference-image input")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent("Template Name") {
                        TextField("For example: Eclipse Familiar", text: $templateName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 270)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Pet Description")
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
                        Text("Art Direction")
                            .font(.caption.bold())
                        TextField("Describe any visual style", text: $artDirection)
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
                    Stepper("Growth Stages: \(stageCount)", value: $stageCount, in: 1...8)
                        .font(.subheadline.bold())
                        .onChange(of: stageCount) { _, newCount in
                            resizeStageNames(to: newCount)
                        }

                    FixedGrid(items: Array(stageNames.indices), columns: 4, spacing: 8) { index in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(index + 1) · \(CustomGrowthStagePlan.thresholds(count: stageCount)[index]) XP")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            TextField("Stage name", text: stageNameBinding(index))
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
                        Label(model.hasImageAPIKey ? "Saved in Keychain" : "Not Saved", systemImage: model.hasImageAPIKey ? "checkmark.shield.fill" : "key.fill")
                            .font(.caption2.bold())
                            .foregroundStyle(model.hasImageAPIKey ? .green : .orange)
                    }
                    SecureField(model.hasImageAPIKey ? "Leave blank to use this user's saved key" : "Installed user's own sk-…", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Save Key") {
                            model.saveImageAPIKey(apiKey)
                            apiKey = ""
                        }
                        .buttonStyle(SoftButtonStyle())
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if model.hasImageAPIKey {
                            Button("Remove") { model.removeImageAPIKey() }
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
                        Text("Generating: \(model.generationStageName)")
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
                    Button("Cancel Generation") { model.cancelTemplateGeneration() }
                        .buttonStyle(SoftButtonStyle())
                }
            } else {
                HStack {
                    Text("You will confirm before generation. About \(stageCount) requests and \(estimatedOutputCost) in output cost will be charged to your own OpenAI API account.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        showGenerationConfirmation = true
                    } label: {
                        Label("Generate Full Growth Line", systemImage: "wand.and.stars")
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
            Text(mode == .faithful ? "High-Fidelity Reference" : "Restyle Reference")
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
                        Text("PNG, JPEG, HEIC, or WebP")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 145)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1)))
            Text(referenceFileName.isEmpty ? "No image selected" : referenceFileName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Button(referenceData == nil ? "Choose Reference Image" : "Change Reference Image") {
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
                Text("PRIVACY BOUNDARY")
                    .font(.subheadline.bold())
                Text("Growth saves, generated stage images, and template manifests stay on this Mac. The API key is stored in macOS Keychain. Only after you confirm generation are the description, selected reference, and same-run stage anchors sent to the OpenAI image API to preserve lineage consistency. Sidekin never uploads Codex conversations, code, or task content.")
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
        panel.title = "Import Sidekin Template"
        panel.prompt = "Import"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "sidekin") ?? .data,
            UTType(filenameExtension: "cainiaopet") ?? .data
        ]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.importTemplate(from: url)
    }

    private func exportTemplatePackage(_ template: CustomPetTemplate) {
        let panel = NSSavePanel()
        panel.title = "Export Sidekin Template"
        panel.prompt = "Export"
        panel.allowedContentTypes = [UTType(filenameExtension: "sidekin") ?? .data]
        panel.nameFieldStringValue = template.name + ".sidekin"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.exportTemplate(template, to: url)
    }

    private func chooseReplacementImage(
        template: CustomPetTemplate,
        stageIndex: Int
    ) {
        let panel = NSOpenPanel()
        panel.title = "Choose a New Stage Image"
        panel.prompt = "Cut Out and Replace"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .heic, .webP]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard fileSize <= 25 * 1_024 * 1_024,
              let data = try? Data(contentsOf: url)
        else {
            model.bannerMessage = "The image could not be read or exceeds 25 MB."
            return
        }
        model.replaceTemplateStage(template, stageIndex: stageIndex, with: data)
    }

    private func chooseReferenceImage() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Pet Reference Image"
        panel.prompt = "Use This Image"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .heic, .webP]
        guard panel.runModal() == .OK,
              let url = panel.url
        else { return }
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard fileSize <= 25 * 1_024 * 1_024 else {
            model.bannerMessage = "The reference image exceeds 25 MB. Compress it before selecting it again."
            return
        }
        guard
              let data = try? Data(contentsOf: url),
              let image = NSImage(data: data)
        else {
            model.bannerMessage = "This image could not be read. Choose a PNG, JPEG, HEIC, or WebP file."
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
                preview(url: rawURL, label: "ORIGINAL")
                preview(url: processedURL, label: "CUTOUT")
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
                        Text(model.activeCustomTemplate.map { "\($0.stages.count)-stage custom growth line" } ?? "Five-stage species evolution")
                            .font(.title2.bold())
                        Text("Select any model to preview it temporarily in the floating pet without changing growth progress.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.hasActivePreview {
                        Button("End Preview") { model.clearPreview() }
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
                                phaseLabel: "Stage \(customStage.index + 1) of \(template.stages.count)",
                                subtitle: customStage.experienceThreshold == 0
                                    ? "Starting form"
                                    : "Unlocks at \(customStage.experienceThreshold) XP",
                                introduction: template.basePrompt,
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
                                introduction: model.activeTheme.formIntroduction(at: stage),
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
                                Text("CODEX STATUS MONITOR")
                                    .font(.headline.bold())
                                Label("LOCAL MONITOR ACTIVE", systemImage: "checkmark.circle.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.green)
                            }
                        }

                        Text("Sidekin reads only task lifecycle events: running, completed, and failed. It does not save prompts, code, tool output, or conversation content.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("CURRENT STATUS")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(model.pet.codexActivity.displayName)
                            .font(.system(size: 23, weight: .bold, design: .rounded))
                        HStack(spacing: 8) {
                            Circle().fill(statusColor).frame(width: 9, height: 9)
                            Text(model.hooksInstalled ? "Official Hooks Installed" : "Read-Only Monitor Mode")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .frame(width: 230, alignment: .leading)
                    .cardStyle()
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("OFFICIAL HOOKS BRIDGE")
                                .font(.headline.bold())
                            Text("When installed, Codex notifies Sprout when tasks start and finish. Existing hooks are preserved.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.hooksInstalled {
                            Button("Remove Integration") { model.uninstallCodexHooks() }
                                .buttonStyle(SoftButtonStyle())
                        } else {
                            Button("Install Codex Integration") { model.installCodexHooks() }
                                .buttonStyle(AccentButtonStyle(color: .mint))
                        }
                    }
                }
                .cardStyle()

                VStack(alignment: .leading, spacing: 14) {
                    Text("STATUS RESPONSE TEST")
                        .font(.headline.bold())
                    Text("Preview the activity animations and growth feedback without running a real task.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        SimulationButton(title: "Running", symbol: "ellipsis", color: .cyan) {
                            model.simulate(.running)
                        }
                        SimulationButton(title: "Complete", symbol: "checkmark", color: .green) {
                            model.simulate(.completed)
                        }
                        SimulationButton(title: "Failed", symbol: "exclamationmark", color: .orange) {
                            model.simulate(.failed)
                        }
                        SimulationButton(title: "Idle", symbol: "pause", color: .mint) {
                            model.simulate(.idle)
                        }
                    }
                }
                .cardStyle()

                VStack(alignment: .leading, spacing: 12) {
                    Label("LOCAL DATA AND PRIVACY", systemImage: "lock.shield.fill")
                        .font(.headline.bold())

                    PathRow(label: "Growth Save", value: model.storageDescription)
                    PathRow(label: "Custom Templates", value: model.templatesDescription)
                    PathRow(label: "Codex Session Directory", value: model.codexSessionsDescription)

                    HStack {
                        Text("Daily care and Codex integration stay entirely local. Descriptions, reference images, and same-run stage anchors reach the OpenAI image API only after you confirm template generation.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Local Data Folder") { model.revealLocalData() }
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
                .frame(width: 60, alignment: .leading)
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

private struct ThemeCategoryFilterButton: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(isSelected ? Color.black : Color.primary.opacity(0.82))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    isSelected ? Color.mint : Color.white.opacity(0.055),
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.mint : Color.white.opacity(0.09), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
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
        .accessibilityLabel("\(theme.displayName), \(isSelected ? "selected" : "select")")
        .help(theme.lineageIntroduction)
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
                Text("\(template.stages.count) STAGES · \(template.generationMode.displayName)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Menu {
                    Button("Rename", systemImage: "pencil", action: renameAction)
                    Button("Export Template", systemImage: "square.and.arrow.up", action: exportAction)
                    Menu("Regenerate Stage with AI", systemImage: "arrow.triangle.2.circlepath") {
                        ForEach(template.stages.indices, id: \.self) { index in
                            Button("\(index + 1) · \(template.stages[index].name)") {
                                regenerateStageAction(index)
                            }
                        }
                    }
                    Menu("Replace with Local Image", systemImage: "photo.badge.arrow.down") {
                        ForEach(template.stages.indices, id: \.self) { index in
                            Button("\(index + 1) · \(template.stages[index].name)") {
                                replaceStageAction(index)
                            }
                        }
                    }
                    Divider()
                    Button("Delete Template", systemImage: "trash", role: .destructive, action: deleteAction)
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
        .accessibilityLabel("\(template.name), \(template.stages.count) stages")
    }
}

private struct EvolutionCard: View {
    let stage: PetStage
    let name: String
    let phaseLabel: String
    let subtitle: String
    let introduction: String
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
                            Text("CURRENT")
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
                    Text(introduction)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary.opacity(0.88))
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                    Label(isPreviewing ? "PREVIEWING" : "PREVIEW", systemImage: isPreviewing ? "eye.fill" : "eye")
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
                Text("\(template.name) · TEMPLATE DETAILS")
                    .font(.headline.bold())
                Spacer()
                Text(template.generationMode.displayName)
                    .font(.caption2.bold())
                    .foregroundStyle(.mint)
            }

            HStack(alignment: .top, spacing: 18) {
                AnchorFact(symbol: "square.stack.3d.up.fill", label: "Growth Stages", value: "\(template.stages.count) stages")
                AnchorFact(symbol: "paintpalette.fill", label: "Art Direction", value: template.artDirection)
                AnchorFact(symbol: "text.bubble.fill", label: "Core Concept", value: template.basePrompt)
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
                Text("\(theme.displayName) · DESIGN ANCHORS")
                    .font(.headline.bold())
                Spacer()
                Text(theme.taxonomyLabel.uppercased())
                    .font(.caption2.bold())
                    .foregroundStyle(theme.secondaryAccentColor)
            }

            Text(theme.lineageIntroduction)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                AnchorFact(symbol: theme.taxonomySymbol, label: "Existence", value: theme.existenceAnchor)
                AnchorFact(symbol: "figure.run", label: "Movement", value: theme.motionAnchor)
                AnchorFact(symbol: "square.3.layers.3d", label: "Silhouette", value: theme.silhouetteAnchor)
                AnchorFact(symbol: "sparkles", label: "Material / Energy", value: "\(theme.materialAnchor) · \(theme.energyAnchor)")
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
