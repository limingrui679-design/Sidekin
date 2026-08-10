import Foundation

public enum PetStage: String, Codable, CaseIterable, Identifiable, Sendable {
    case egg
    case hatchling
    case juvenile
    case ascended
    case legendary

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .egg: "第一阶段 · 核卵"
        case .hatchling: "第二阶段 · 初醒"
        case .juvenile: "第三阶段 · 锐变"
        case .ascended: "第四阶段 · 觉醒"
        case .legendary: "第五阶段 · 冠冕"
        }
    }

    public var shortName: String {
        switch self {
        case .egg: "核卵"
        case .hatchling: "初醒"
        case .juvenile: "锐变"
        case .ascended: "觉醒"
        case .legendary: "冠冕"
        }
    }

    public var subtitle: String {
        switch self {
        case .egg: "专属物种锚点正在容器中成形"
        case .hatchling: "幼体轮廓与运动方式第一次显现"
        case .juvenile: "主题附肢、工具与能量器官开始成熟"
        case .ascended: "战斗姿态和能力结构完成质变"
        case .legendary: "血统特征抵达独一无二的巅峰"
        }
    }

    public var isEvolved: Bool {
        rank >= PetStage.ascended.rank
    }

    public var isFinal: Bool {
        self == .legendary
    }

    public var rank: Int {
        switch self {
        case .egg: 0
        case .hatchling: 1
        case .juvenile: 2
        case .ascended: 3
        case .legendary: 4
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        // Four-stage saves used guardian/dreamer as two terminal branches. Both
        // migrate to the fourth stage so an existing pet never loses progress.
        if value == "guardian" || value == "dreamer" {
            self = .ascended
            return
        }

        guard let stage = Self(rawValue: value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown pet stage: \(value)"
            )
        }
        self = stage
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum CodexActivity: String, Codable, CaseIterable, Identifiable, Sendable {
    case idle
    case running
    case completed
    case failed

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .idle: "休息中"
        case .running: "Codex 正在工作"
        case .completed: "任务完成"
        case .failed: "任务遇到问题"
        }
    }
}

public enum PetCareAction: String, Codable, Sendable {
    case feed
    case play
    case sleepOrWake
}

public enum PetVisualTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case nova
    case mecha
    case street
    case samurai
    case abyss
    case volcanic
    case candy
    case wasteland
    case phantom
    case totem

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .nova: "星核竞技"
        case .mecha: "先锋机甲"
        case .street: "街头乱斗"
        case .samurai: "樱刃武者"
        case .abyss: "深海猎潮"
        case .volcanic: "熔岩暴君"
        case .candy: "糖果派对"
        case .wasteland: "荒原拾荒"
        case .phantom: "幽影幻术"
        case .totem: "森灵图腾"
        }
    }

    public var subtitle: String {
        switch self {
        case .nova: "晶体能量 · 星界赛场"
        case .mecha: "陶瓷装甲 · 警戒橙核心"
        case .street: "涂鸦护甲 · 酸性霓虹"
        case .samurai: "朱漆武甲 · 樱华能量"
        case .abyss: "深海甲壳 · 潮汐荧光"
        case .volcanic: "黑曜岩层 · 熔火裂隙"
        case .candy: "糖果玩具 · 软糖能量"
        case .wasteland: "废土拼装 · 锈蚀黄铜"
        case .phantom: "暗影魔甲 · 幽绿灵质"
        case .totem: "木石雕甲 · 琥珀树能"
        }
    }

    public var symbolName: String {
        switch self {
        case .nova: "sparkles"
        case .mecha: "cpu.fill"
        case .street: "bolt.fill"
        case .samurai: "fan.fill"
        case .abyss: "water.waves"
        case .volcanic: "flame.fill"
        case .candy: "heart.fill"
        case .wasteland: "wrench.and.screwdriver.fill"
        case .phantom: "moon.stars.fill"
        case .totem: "leaf.fill"
        }
    }

    public var speciesAnchor: String {
        switch self {
        case .nova: "星晶月兔"
        case .mecha: "轮足机械獒"
        case .street: "涂鸦壁虎"
        case .samurai: "赤狐 × 鹤"
        case .abyss: "蝾螈 × 蟹 × 蝠鲼"
        case .volcanic: "穿山甲 × 甲龙"
        case .candy: "气球兔 × 软糖灵"
        case .wasteland: "装甲耳廓狐"
        case .phantom: "蛾猫幽灵"
        case .totem: "古树鹿 × 野猪"
        }
    }

    public var silhouetteAnchor: String {
        switch self {
        case .nova: "月牙长耳、彗尾披帛、星晶长弓"
        case .mecha: "低矮宽肩、轮足、展开式炮塔脊"
        case .street: "细长吸盘肢、喷漆罐尾、滑板侧线"
        case .samurai: "鹤腿侧身、扇形羽尾、弧月翼刃"
        case .abyss: "横向宽体、多鳍多足、巨环蝠鲼翼"
        case .volcanic: "拱背贴地、层叠岩甲、巨型锤尾"
        case .candy: "圆润弹体、飘带长耳、环形气球轨"
        case .wasteland: "巨耳四足、背负模块、吊臂与电台阵列"
        case .phantom: "无脚烟尾、斗篷蛾翼、月蚀圆盘"
        case .totem: "四足根蹄、野猪肩峰、世界树冠角"
        }
    }

    public var motionAnchor: String {
        switch self {
        case .nova: "轻盈跃迁与悬空拉弓"
        case .mecha: "四足贴地攻城冲锋"
        case .street: "蹲伏滑行与单手倒立"
        case .samurai: "侧身拔刀与单足鹤立"
        case .abyss: "水平漂浮游动"
        case .volcanic: "卷身蓄力后低头撞击"
        case .candy: "弹跳、悬浮与空翻"
        case .wasteland: "四足侧步与负载奔跑"
        case .phantom: "倒悬漂浮与侧身施术"
        case .totem: "沉稳四足踏地召根"
        }
    }

    public var materialAnchor: String {
        switch self {
        case .nova: "半透明星晶与深蓝柔性甲"
        case .mecha: "白色陶瓷板与枪灰机械关节"
        case .street: "磨损橡胶、贴纸与喷漆塑料"
        case .samurai: "朱漆、黑铁、和纸与淡金绳结"
        case .abyss: "珍珠甲壳、湿润皮肤与透明鳍"
        case .volcanic: "黑曜岩、玄武岩角与熔火裂缝"
        case .candy: "透明软糖、糖纸、糖霜与果冻"
        case .wasteland: "锈铜、旧帆布、拼装钢板与线缆"
        case .phantom: "天鹅绒暗影、烟雾与月银薄片"
        case .totem: "雕刻木、苔藓石与树脂琥珀"
        }
    }

    public var energyAnchor: String {
        switch self {
        case .nova: "四芒星核与引力轨道"
        case .mecha: "橙色六边反应炉"
        case .street: "酸绿声波与红色涂鸦爆点"
        case .samurai: "沿刃聚合的樱瓣弧月"
        case .abyss: "青蓝生物荧光与水压环"
        case .volcanic: "橙白地火与冠脊喷发"
        case .candy: "彩虹气泡与心形糖核"
        case .wasteland: "琥珀回收电池与沙尘电弧"
        case .phantom: "幽绿假面火与月蚀光盘"
        case .totem: "琥珀树心与发光年轮"
        }
    }

    public func formName(at stage: PetStage) -> String {
        let names: [String]
        switch self {
        case .nova:
            names = ["星梭晶卵", "月跃幼兔", "星晶斥候", "星弓巡猎者", "天穹领航兔"]
        case .mecha:
            names = ["折叠六角舱", "双轮侦察机", "轮足机械獒", "展开堡垒獒", "天虎机动要塞"]
        case .street:
            names = ["摇漆罐卵", "趴地小壁虎", "滑板涂鸦客", "音浪乱斗手", "环城轰鸣壁虎"]
        case .samurai:
            names = ["折扇纹卵", "鞘尾幼狐", "樱刃小将", "鹤步剑豪", "千瓣翼刃阵主"]
        case .abyss:
            names = ["潮泡囊卵", "六鳍漂游螈", "钳翼猎潮者", "深渊潮骑", "巨环王潮鳐兽"]
        case .volcanic:
            names = ["多面熔核石", "炭爪幼兽", "卷甲穿山兽", "锤尾攻城兽", "熔冠地脉龙"]
        case .candy:
            names = ["扭结糖纸茧", "弹跳软糖兔", "太妃杂技兽", "嘉年华魔术兽", "星糖梦工兽"]
        case .wasteland:
            names = ["锈罐孵化仓", "拾件幼狐", "负载斥候", "吊臂机匠", "电台巨构猎狐"]
        case .phantom:
            names = ["月纹幽灯茧", "倒悬雾翼灵", "影幕蛾猫", "月蚀术兽", "无相夜幕兽"]
        case .totem:
            names = ["裂纹琥珀种", "根蹄芽鹿", "苔甲幼麋", "森纹角兽", "世界树冠古鹿"]
        }
        return names[stage.rank]
    }
}

public enum PetTemplateGenerationMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case text
    case restyle
    case faithful

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .text: "文字原创"
        case .restyle: "参考图改画风"
        case .faithful: "参考图高相似"
        }
    }

    public var requiresReferenceImage: Bool {
        self != .text
    }
}

public enum PetImageGenerationQuality: String, Codable, CaseIterable, Identifiable, Sendable {
    case low
    case medium
    case high

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .low: "草稿"
        case .medium: "标准"
        case .high: "最终"
        }
    }

    public var detail: String {
        switch self {
        case .low: "速度最快，适合先看轮廓"
        case .medium: "细节与费用较均衡"
        case .high: "细节最多，费用最高"
        }
    }

    /// Published GPT Image 2 output-only estimate for a 1024×1024 image.
    /// Text and reference-image input tokens are intentionally excluded because
    /// their cost depends on the concrete request.
    public var estimatedOutputUSDPerSquareImage: Double {
        switch self {
        case .low: 0.006
        case .medium: 0.053
        case .high: 0.211
        }
    }

    public func estimatedOutputUSD(stageCount: Int) -> Double {
        estimatedOutputUSDPerSquareImage * Double(max(0, stageCount))
    }
}

public struct CustomPetStageDefinition: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var index: Int
    public var name: String
    public var prompt: String
    public var experienceThreshold: Int
    public var assetFileName: String

    public init(
        id: String = UUID().uuidString,
        index: Int,
        name: String,
        prompt: String = "",
        experienceThreshold: Int,
        assetFileName: String
    ) {
        self.id = id
        self.index = index
        self.name = name
        self.prompt = prompt
        self.experienceThreshold = experienceThreshold
        self.assetFileName = assetFileName
    }
}

public struct CustomPetTemplate: Codable, Equatable, Identifiable, Sendable {
    public var schemaVersion: Int
    public var id: String
    public var name: String
    public var basePrompt: String
    public var artDirection: String
    public var generationMode: PetTemplateGenerationMode
    /// Optional so templates created by v1.1 remain decodable.
    public var generationQuality: PetImageGenerationQuality?
    public var referenceFileName: String?
    public var createdAt: Date
    public var fallbackTheme: PetVisualTheme
    public var stages: [CustomPetStageDefinition]

    public init(
        schemaVersion: Int = 1,
        id: String = UUID().uuidString,
        name: String,
        basePrompt: String,
        artDirection: String,
        generationMode: PetTemplateGenerationMode,
        generationQuality: PetImageGenerationQuality? = nil,
        referenceFileName: String? = nil,
        createdAt: Date = Date(),
        fallbackTheme: PetVisualTheme = .nova,
        stages: [CustomPetStageDefinition]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.basePrompt = basePrompt
        self.artDirection = artDirection
        self.generationMode = generationMode
        self.generationQuality = generationQuality
        self.referenceFileName = referenceFileName
        self.createdAt = createdAt
        self.fallbackTheme = fallbackTheme
        self.stages = stages.sorted { $0.index < $1.index }
    }

    public func stageIndex(for experience: Int) -> Int {
        let ordered = stages.sorted { $0.experienceThreshold < $1.experienceThreshold }
        guard !ordered.isEmpty else { return 0 }
        return ordered.lastIndex { experience >= $0.experienceThreshold } ?? 0
    }

    public var resolvedGenerationQuality: PetImageGenerationQuality {
        generationQuality ?? .medium
    }
}

public enum CustomGrowthStagePlan {
    public static let minimumStageCount = 1
    public static let maximumStageCount = 8

    private static let canonicalThresholds = [0, 20, 75, 180, 360]
    private static let canonicalNames = ["核卵", "初醒", "锐变", "觉醒", "冠冕"]
    private static let extendedNames = ["起源", "幼生", "萌芽", "锐变", "成熟", "觉醒", "超越", "冠冕"]

    public static func clampedCount(_ count: Int) -> Int {
        min(maximumStageCount, max(minimumStageCount, count))
    }

    public static func defaultNames(count: Int) -> [String] {
        let count = clampedCount(count)
        if count == canonicalNames.count { return canonicalNames }
        if count == 1 { return ["完整形态"] }
        if count == extendedNames.count { return extendedNames }

        return (0..<count).map { index in
            let position = Double(index) / Double(count - 1)
            let extendedIndex = Int((position * Double(extendedNames.count - 1)).rounded())
            return extendedNames[extendedIndex]
        }
    }

    public static func thresholds(count: Int) -> [Int] {
        let count = clampedCount(count)
        if count == 1 { return [0] }
        if count == canonicalThresholds.count { return canonicalThresholds }

        return (0..<count).map { index in
            let normalized = Double(index) / Double(count - 1)
            let position = normalized * Double(canonicalThresholds.count - 1)
            let lower = min(canonicalThresholds.count - 1, Int(floor(position)))
            let upper = min(canonicalThresholds.count - 1, lower + 1)
            let fraction = position - Double(lower)
            let value = Double(canonicalThresholds[lower])
                + Double(canonicalThresholds[upper] - canonicalThresholds[lower]) * fraction
            return Int(value.rounded())
        }
    }

    public static func canonicalStage(customIndex: Int, stageCount: Int) -> PetStage {
        let count = clampedCount(stageCount)
        guard count > 1 else { return .legendary }
        let clampedIndex = min(count - 1, max(0, customIndex))
        let rank = Int((Double(clampedIndex) / Double(count - 1) * 4).rounded())
        return PetStage.allCases[min(4, max(0, rank))]
    }
}

public struct PetTemplateSelection: Codable, Equatable, Sendable {
    /// `theme` keeps old skin saves decodable; decorations are intentionally ignored.
    public var theme: PetVisualTheme?
    public var customTemplateID: String?

    public init(
        theme: PetVisualTheme? = .nova,
        customTemplateID: String? = nil
    ) {
        self.theme = theme
        self.customTemplateID = customTemplateID
    }

    public var resolvedTheme: PetVisualTheme {
        theme ?? .nova
    }
}

public struct PetStats: Codable, Equatable, Sendable {
    public var hunger: Double
    public var mood: Double
    public var energy: Double

    public init(hunger: Double = 76, mood: Double = 82, energy: Double = 78) {
        self.hunger = hunger
        self.mood = mood
        self.energy = energy
        clamp()
    }

    public mutating func clamp() {
        hunger = min(100, max(0, hunger))
        mood = min(100, max(0, mood))
        energy = min(100, max(0, energy))
    }
}

public struct PetSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var name: String
    public var createdAt: Date
    public var lastUpdatedAt: Date
    public var activityChangedAt: Date
    public var stats: PetStats
    public var experience: Int
    public var stage: PetStage
    public var isSleeping: Bool
    public var codexActivity: CodexActivity
    /// The JSON key remains `wardrobe` so existing local saves migrate without loss.
    public var wardrobe: PetTemplateSelection
    public var careAffinity: Int
    public var sparkAffinity: Int
    public var feedCount: Int
    public var playCount: Int
    public var restCount: Int
    public var completedTasks: Int
    public var failedTasks: Int
    public var processedCodexSignals: [String]?
    public var lastCodexSignalAt: Date?
    public var lastCodexSignalActivity: CodexActivity?

    public init(name: String = "芽芽", now: Date = Date()) {
        self.schemaVersion = 3
        self.name = name
        self.createdAt = now
        self.lastUpdatedAt = now
        self.activityChangedAt = now
        self.stats = PetStats()
        self.experience = 0
        self.stage = .egg
        self.isSleeping = false
        self.codexActivity = .idle
        self.wardrobe = PetTemplateSelection()
        self.careAffinity = 0
        self.sparkAffinity = 0
        self.feedCount = 0
        self.playCount = 0
        self.restCount = 0
        self.completedTasks = 0
        self.failedTasks = 0
        self.processedCodexSignals = []
        self.lastCodexSignalAt = nil
        self.lastCodexSignalActivity = nil
    }

    public var wellbeing: Double {
        (stats.hunger + stats.mood + stats.energy) / 3
    }

    public var nextStageThreshold: Int? {
        switch stage {
        case .egg: 20
        case .hatchling: 75
        case .juvenile: 180
        case .ascended: 360
        case .legendary: nil
        }
    }

    public var stageProgress: Double {
        switch stage {
        case .egg:
            min(1, Double(experience) / 20)
        case .hatchling:
            min(1, max(0, Double(experience - 20) / 55))
        case .juvenile:
            min(1, max(0, Double(experience - 75) / 105))
        case .ascended:
            min(1, max(0, Double(experience - 180) / 180))
        case .legendary:
            1
        }
    }
}
