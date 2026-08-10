import AppKit
import CainiaoPetCore
import CainiaoPetCreator
import Foundation

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) throws {
    guard condition() else { throw TestFailure(description: message) }
}

private var passed = 0

@MainActor
private func makePNG(
    side: CGFloat = 160,
    draw: () -> Void
) throws -> Data {
    let image = NSImage(size: NSSize(width: side, height: side))
    image.lockFocus()
    draw()
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation,
          let representation = NSBitmapImageRep(data: tiff),
          let data = representation.representation(using: .png, properties: [:])
    else { throw TestFailure(description: "无法创建合成测试图") }
    return data
}

@MainActor
private func solidPNG(_ color: NSColor) throws -> Data {
    try makePNG {
        color.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 160, height: 160)).fill()
    }
}

@MainActor
private func test(_ name: String, _ body: () throws -> Void) {
    do {
        try body()
        passed += 1
        print("✓ \(name)")
    } catch {
        fputs("✗ \(name): \(error)\n", stderr)
        exit(1)
    }
}

test("新宠物从蛋形态开始") {
    let pet = PetSnapshot(now: Date(timeIntervalSince1970: 1_000))
    try expect(pet.stage == .egg, "初始形态不是蛋")
    try expect(pet.experience == 0, "初始经验值不为零")
    try expect(pet.wellbeing > 70, "初始状态过低")
}

test("喂食会恢复饥饿值并孵化") {
    let start = Date(timeIntervalSince1970: 1_000)
    var pet = PetSnapshot(now: start)
    pet.stats.hunger = 20

    for offset in 1...3 {
        PetLifecycleEngine.perform(
            .feed,
            on: &pet,
            at: start.addingTimeInterval(TimeInterval(offset))
        )
    }

    try expect(pet.stage == .hatchling, "三次喂食后未进入初醒阶段")
    try expect(pet.feedCount == 3, "喂食次数错误")
    try expect(pet.stats.hunger > 90, "饥饿值没有恢复")
}

test("Codex 完成任务会推进到第三成长阶段") {
    let start = Date(timeIntervalSince1970: 2_000)
    var pet = PetSnapshot(now: start)

    for offset in 1...5 {
        PetLifecycleEngine.apply(
            .completed,
            to: &pet,
            at: start.addingTimeInterval(TimeInterval(offset)),
            eventID: "guardian-\(offset)"
        )
    }

    try expect(pet.experience == 75, "任务经验累计错误")
    try expect(pet.stage == .juvenile, "没有进入锐变阶段")
    try expect(pet.completedTasks == 5, "完成任务计数错误")
}

test("持续互动会推进到第四成长阶段") {
    let start = Date(timeIntervalSince1970: 3_000)
    var pet = PetSnapshot(now: start)

    for offset in 1...20 {
        PetLifecycleEngine.perform(
            .play,
            on: &pet,
            at: start.addingTimeInterval(TimeInterval(offset))
        )
    }

    try expect(pet.experience == 180, "互动经验累计错误")
    try expect(pet.stage == .ascended, "没有进入觉醒阶段")
    try expect(pet.playCount == 20, "玩耍次数错误")
    try expect(pet.sparkAffinity > pet.careAffinity, "进化倾向错误")
}

test("长期完成任务会推进到第五成长阶段") {
    let start = Date(timeIntervalSince1970: 3_500)
    var pet = PetSnapshot(now: start)

    for offset in 1...24 {
        PetLifecycleEngine.apply(
            .completed,
            to: &pet,
            at: start.addingTimeInterval(TimeInterval(offset)),
            eventID: "legendary-\(offset)"
        )
    }

    try expect(pet.experience == 360, "第五阶段经验累计错误")
    try expect(pet.stage == .legendary, "没有进入冠冕阶段")
    try expect(pet.nextStageThreshold == nil, "最终阶段仍显示下一阈值")
}

test("睡眠会恢复精力并保持数值边界") {
    let start = Date(timeIntervalSince1970: 4_000)
    var pet = PetSnapshot(now: start)
    pet.stats.energy = 30
    pet.isSleeping = true

    PetLifecycleEngine.advance(&pet, to: start.addingTimeInterval(3_600))

    try expect(pet.stats.energy > 45, "睡眠没有恢复精力")
    try expect(pet.stats.energy <= 100, "精力超过上限")
    try expect(pet.stats.hunger >= 0, "饥饿值低于下限")
}

test("完成动画会在短暂展示后回到待机") {
    let start = Date(timeIntervalSince1970: 5_000)
    var pet = PetSnapshot(now: start)

    PetLifecycleEngine.apply(.completed, to: &pet, at: start.addingTimeInterval(1))
    try expect(pet.codexActivity == .completed, "未进入完成状态")

    PetLifecycleEngine.advance(&pet, to: start.addingTimeInterval(20))
    try expect(pet.codexActivity == .idle, "瞬时动画后未回到待机")
}

test("本地存档可完整往返") {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let persistence = PetPersistence(stateURL: directory.appendingPathComponent("pet.json"))
    var expected = PetSnapshot(now: Date(timeIntervalSince1970: 10_000))
    expected.wardrobe = PetTemplateSelection(
        theme: .street,
        customTemplateID: UUID().uuidString
    )
    expected.experience = 42

    try persistence.save(expected)
    let actual = try persistence.load()
    try expect(actual == expected, "存档内容不一致")
}

test("旧装饰存档会忽略已移除字段并安全迁移") {
    let oldWardrobeJSON = #"{"hat":"sprout","face":"none","aura":"sparkles"}"#
    let oldWardrobe = try JSONDecoder().decode(
        PetTemplateSelection.self,
        from: Data(oldWardrobeJSON.utf8)
    )

    try expect(oldWardrobe.theme == nil, "旧存档不应伪造模板字段")
    try expect(oldWardrobe.customTemplateID == nil, "旧装饰字段被错误迁移成自定义模板")
    try expect(oldWardrobe.resolvedTheme == .nova, "旧存档未回退到星核竞技")
}

test("自定义成长计划支持一到八阶段") {
    for count in 1...8 {
        let names = CustomGrowthStagePlan.defaultNames(count: count)
        let thresholds = CustomGrowthStagePlan.thresholds(count: count)
        try expect(names.count == count, "阶段名称数量错误：\(count)")
        try expect(Set(names).count == count, "默认阶段名称重复：\(count)")
        try expect(thresholds.count == count, "阶段阈值数量错误：\(count)")
        try expect(thresholds.first == 0, "第一阶段不是从 0 XP 开始")
        try expect(thresholds == thresholds.sorted(), "阶段阈值没有递增")
    }
    try expect(
        CustomGrowthStagePlan.thresholds(count: 5) == [0, 20, 75, 180, 360],
        "五阶段计划没有复用既有成长节奏"
    )
}

test("三档质量会给出当前 1024 方图输出费用估算") {
    try expect(
        abs(PetImageGenerationQuality.low.estimatedOutputUSD(stageCount: 5) - 0.030) < 0.000_001,
        "草稿质量费用估算错误"
    )
    try expect(
        abs(PetImageGenerationQuality.medium.estimatedOutputUSD(stageCount: 5) - 0.265) < 0.000_001,
        "标准质量费用估算错误"
    )
    try expect(
        abs(PetImageGenerationQuality.high.estimatedOutputUSD(stageCount: 5) - 1.055) < 0.000_001,
        "最终质量费用估算错误"
    )
}

test("自定义模板会按经验值切换正确阶段") {
    let thresholds = CustomGrowthStagePlan.thresholds(count: 3)
    let template = CustomPetTemplate(
        name: "三阶段伙伴",
        basePrompt: "测试",
        artDirection: "测试",
        generationMode: .text,
        stages: thresholds.enumerated().map { index, threshold in
            CustomPetStageDefinition(
                index: index,
                name: "阶段 \(index + 1)",
                experienceThreshold: threshold,
                assetFileName: "stage-\(index + 1).png"
            )
        }
    )
    try expect(template.stageIndex(for: 0) == 0, "初始经验阶段错误")
    try expect(template.stageIndex(for: thresholds[1] - 1) == 0, "阈值前提前进化")
    try expect(template.stageIndex(for: thresholds[1]) == 1, "中间阶段未按阈值解锁")
    try expect(template.stageIndex(for: thresholds[2]) == 2, "最终阶段未按阈值解锁")
}

test("自定义模板会原子写入并完整读取") {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let stages = CustomGrowthStagePlan.thresholds(count: 3).enumerated().map { index, threshold in
        CustomPetStageDefinition(
            index: index,
            name: "阶段 \(index + 1)",
            experienceThreshold: threshold,
            assetFileName: String(format: "stage-%02d.png", index + 1)
        )
    }
    let template = CustomPetTemplate(
        name: "测试伙伴",
        basePrompt: "一只测试生物",
        artDirection: "竞技游戏角色",
        generationMode: .text,
        createdAt: Date(timeIntervalSince1970: 20_000),
        fallbackTheme: .totem,
        stages: stages
    )
    let images = [
        try solidPNG(.systemBlue),
        try solidPNG(.systemPurple),
        try solidPNG(.systemOrange)
    ]
    let store = PetTemplateStore(templatesDirectory: directory)
    try store.install(template: template, stageImages: images)

    let loaded = try store.load(id: template.id)
    try expect(loaded == template, "模板清单读取不一致")
    let allTemplates = try store.loadAll()
    try expect(allTemplates == [template], "模板列表读取不一致")
    let secondURL = store.assetURL(templateID: template.id, fileName: "stage-02.png")
    try expect(secondURL != nil, "第二阶段资源不存在")
    let secondData = try Data(contentsOf: secondURL!)
    try expect(secondData == images[1], "阶段图片内容不一致")
}

test("模板仓库拒绝路径穿越文件名") {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let template = CustomPetTemplate(
        name: "非法模板",
        basePrompt: "测试",
        artDirection: "测试",
        generationMode: .text,
        stages: [
            CustomPetStageDefinition(
                index: 0,
                name: "阶段 1",
                experienceThreshold: 0,
                assetFileName: "../escape.png"
            )
        ]
    )
    let store = PetTemplateStore(templatesDirectory: directory)
    do {
        try store.install(template: template, stageImages: [Data([1])])
        throw TestFailure(description: "非法资源路径被模板仓库接受")
    } catch PetTemplateStoreError.invalidStageLayout {
        // Expected.
    }
}

test("模板支持重命名、阶段替换、导出导入与删除") {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PetTemplateStore(templatesDirectory: directory)
    let template = CustomPetTemplate(
        name: "待管理模板",
        basePrompt: "测试",
        artDirection: "测试",
        generationMode: .faithful,
        generationQuality: .low,
        referenceFileName: "reference.png",
        stages: [
            CustomPetStageDefinition(
                index: 0,
                name: "幼体",
                experienceThreshold: 0,
                assetFileName: "stage-01.png"
            ),
            CustomPetStageDefinition(
                index: 1,
                name: "成体",
                experienceThreshold: 180,
                assetFileName: "stage-02.png"
            )
        ]
    )
    let firstStage = try solidPNG(.systemPink)
    let secondStage = try solidPNG(.systemTeal)
    let replacementStage = try solidPNG(.systemIndigo)
    let referenceImage = try solidPNG(.systemYellow)
    try store.install(
        template: template,
        stageImages: [firstStage, secondStage],
        referenceImage: referenceImage
    )
    let renamed = try store.rename(id: template.id, to: "已重命名模板")
    try expect(renamed.name == "已重命名模板", "模板重命名未落盘")

    let replaced = try store.replaceStageImage(
        templateID: template.id,
        stageIndex: 1,
        imageData: replacementStage,
        prompt: "replacement",
        generationQuality: .high
    )
    try expect(replaced.stages[1].prompt == "replacement", "阶段替换提示未更新")
    try expect(replaced.resolvedGenerationQuality == .high, "阶段替换质量未更新")
    let replacedData = try store.assetData(templateID: template.id, fileName: "stage-02.png")
    try expect(replacedData == replacementStage, "阶段图片没有原位替换")

    let package = try store.exportPackage(id: template.id)
    let imported = try store.importPackage(package)
    try expect(imported.id != template.id, "重复导入没有生成安全的新标识")
    try expect(imported.name == renamed.name, "导入后模板名称不一致")
    let importedReference = try store.referenceData(template: imported)
    try expect(importedReference == referenceImage, "导入后参考图不一致")
    let importedTemplates = try store.loadAll()
    try expect(importedTemplates.count == 2, "导入模板没有加入模板库")

    var corruptPackage = package
    let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    guard let signatureRange = corruptPackage.range(of: pngSignature) else {
        throw TestFailure(description: "测试模板包内没有 PNG 数据")
    }
    corruptPackage.replaceSubrange(
        signatureRange,
        with: Data(repeating: 0, count: pngSignature.count)
    )
    do {
        _ = try store.importPackage(corruptPackage)
        throw TestFailure(description: "损坏图片模板包被成功导入")
    } catch PetTemplateStoreError.invalidPackage {
        // Expected.
    }

    try store.remove(id: template.id)
    let deletedTemplate = try store.load(id: template.id)
    try expect(deletedTemplate == nil, "删除后模板仍然存在")
}

test("模板仓库拒绝伪装成 PNG 的无效图片") {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PetTemplateStore(templatesDirectory: directory)
    let template = CustomPetTemplate(
        name: "坏图测试",
        basePrompt: "测试",
        artDirection: "测试",
        generationMode: .text,
        stages: [
            CustomPetStageDefinition(
                index: 0,
                name: "幼体",
                experienceThreshold: 0,
                assetFileName: "stage-01.png"
            )
        ]
    )
    do {
        try store.install(
            template: template,
            stageImages: [Data("not-a-real-png".utf8)]
        )
        throw TestFailure(description: "无效图片被模板仓库接受")
    } catch PetTemplateStoreError.invalidImage {
        // Expected.
    }
}

test("生成恢复任务会先保存付费原图并支持从阶段重做") {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PetGenerationJobStore(jobsDirectory: directory)
    let request = PetGenerationRequest(
        templateName: "恢复测试",
        description: "一只测试宠物",
        artDirection: "竞技游戏角色",
        mode: .text,
        quality: .low,
        stageNames: ["蛋", "幼体", "成体"]
    )
    var job = try store.create(request: request, normalizedReference: nil)
    let paidRaw = Data("paid-api-result".utf8)
    try store.saveRawStage(jobID: job.id, stageIndex: 0, data: paidRaw)
    job = try store.load(id: job.id)
    try expect(job.completedCount == 0, "只有原图时不应伪报阶段已完成")
    let recoveredRaw = try store.rawStageData(jobID: job.id, stageIndex: 0)
    try expect(recoveredRaw == paidRaw, "API 原图没有先于处理结果保存")
    try expect(store.rawStageURL(jobID: job.id, stageIndex: 0) != nil, "API 原图预览不存在")

    let definition = CustomPetStageDefinition(
        index: 0,
        name: "蛋",
        prompt: "stage prompt",
        experienceThreshold: 0,
        assetFileName: "stage-01.png"
    )
    job = try store.saveProcessedStage(
        jobID: job.id,
        definition: definition,
        data: Data("transparent-preview".utf8)
    )
    try expect(job.completedCount == 1, "处理完成后恢复点没有推进")
    try expect(store.processedStageURL(jobID: job.id, stageIndex: 0) != nil, "抠图预览不存在")
    _ = try store.updateState(jobID: job.id, state: .failed, errorMessage: "mock failure")
    let failedJob = try store.load(id: job.id)
    try expect(failedJob.lastError == "mock failure", "失败原因没有持久化")

    job = try store.restart(jobID: job.id, fromStage: 0)
    try expect(job.completedCount == 0, "从阶段重做没有清除后续恢复点")
    let restartedRaw = try store.rawStageData(jobID: job.id, stageIndex: 0)
    try expect(restartedRaw == nil, "重做后旧原图仍存在")
}

test("单阶段付费重绘也会保留原图恢复点") {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PetTemplateStore(templatesDirectory: directory)
    let template = CustomPetTemplate(
        name: "单阶段恢复测试",
        basePrompt: "测试",
        artDirection: "竞技游戏角色",
        generationMode: .text,
        stages: [
            CustomPetStageDefinition(
                index: 0,
                name: "幼体",
                experienceThreshold: 0,
                assetFileName: "stage-01.png"
            )
        ]
    )
    try store.install(template: template, stageImages: [try solidPNG(.systemBlue)])
    let paidRaw = Data("single-stage-paid-result".utf8)
    try store.savePendingReplacementRaw(
        templateID: template.id,
        stageIndex: 0,
        data: paidRaw
    )
    let savedRaw = try store.pendingReplacementRaw(templateID: template.id, stageIndex: 0)
    try expect(savedRaw == paidRaw, "单阶段付费原图没有持久化")
    try store.clearPendingReplacementRaw(templateID: template.id, stageIndex: 0)
    let clearedRaw = try store.pendingReplacementRaw(templateID: template.id, stageIndex: 0)
    try expect(clearedRaw == nil, "阶段替换完成后恢复点没有清理")
}

test("生成提示强制阶段结构差异与纯色抠图背景") {
    let request = PetGenerationRequest(
        templateName: "月蚀伙伴",
        description: "一只带月纹的猫形生物",
        artDirection: "竞技游戏 3D 建模",
        mode: .faithful,
        stageNames: CustomGrowthStagePlan.defaultNames(count: 5),
        referenceImage: Data([1])
    )
    let prompt = PetLineageGenerator.prompt(
        request: request,
        stageIndex: 3,
        stageName: request.stageNames[3]
    )
    try expect(prompt.contains("genuinely different body proportion"), "没有要求阶段结构差异")
    try expect(prompt.contains("#FF00FF"), "没有要求可抠图纯色背景")
    try expect(prompt.contains(request.artDirection), "没有传入用户画风")
    try expect(prompt.contains("Preserve the uploaded subject's identity"), "高相似模式没有保留主体约束")
}

test("生成图片会标准化为透明 1254 方形资源") {
    let source = NSImage(size: NSSize(width: 160, height: 160))
    source.lockFocus()
    NSColor.magenta.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: 160, height: 160)).fill()
    NSColor.systemBlue.setFill()
    NSBezierPath(ovalIn: NSRect(x: 45, y: 28, width: 70, height: 104)).fill()
    source.unlockFocus()

    guard let tiff = source.tiffRepresentation,
          let representation = NSBitmapImageRep(data: tiff),
          let sourcePNG = representation.representation(using: .png, properties: [:])
    else { throw TestFailure(description: "无法创建合成测试图") }

    let output = try PetImageProcessor.prepareGeneratedAsset(sourcePNG)
    guard let outputRep = NSBitmapImageRep(data: output) else {
        throw TestFailure(description: "处理结果不是有效图片")
    }
    try expect(outputRep.pixelsWide == 1_254, "输出宽度不是 1254")
    try expect(outputRep.pixelsHigh == 1_254, "输出高度不是 1254")
    try expect((outputRep.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.05, "输出角落没有透明")
    try expect((outputRep.colorAt(x: 627, y: 627)?.alphaComponent ?? 0) > 0.8, "宠物主体被错误抠除")
}

test("边缘连通抠图会保留主体内部的洋红与紫色") {
    let sourcePNG = try makePNG {
        NSColor.magenta.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 160, height: 160)).fill()
        NSColor(calibratedRed: 0.42, green: 0.08, blue: 0.62, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 35, y: 20, width: 90, height: 120)).fill()
        NSColor.magenta.setFill()
        NSBezierPath(ovalIn: NSRect(x: 66, y: 66, width: 28, height: 28)).fill()
    }
    let output = try PetImageProcessor.prepareGeneratedAsset(sourcePNG)
    guard let rep = NSBitmapImageRep(data: output) else {
        throw TestFailure(description: "无法读取连通抠图输出")
    }
    try expect((rep.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.05, "边缘洋红背景没有删除")
    try expect((rep.colorAt(x: 627, y: 627)?.alphaComponent ?? 0) > 0.8, "主体内部洋红被错误挖空")
}

test("抠图会从画布边缘自适应识别非洋红纯色背景") {
    let sourcePNG = try makePNG {
        NSColor(calibratedRed: 0.02, green: 0.82, blue: 0.88, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 160, height: 160)).fill()
        NSColor.systemPink.setFill()
        NSBezierPath(ovalIn: NSRect(x: 42, y: 25, width: 76, height: 110)).fill()
    }
    let output = try PetImageProcessor.prepareGeneratedAsset(sourcePNG)
    guard let rep = NSBitmapImageRep(data: output) else {
        throw TestFailure(description: "无法读取自适应抠图输出")
    }
    try expect((rep.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.05, "自适应背景没有变透明")
    try expect((rep.colorAt(x: 627, y: 627)?.alphaComponent ?? 0) > 0.8, "粉色主体被自适应背景误伤")
}

test("旧版两条终局进化会无损迁移到第四阶段") {
    let guardian = try JSONDecoder().decode(PetStage.self, from: Data(#""guardian""#.utf8))
    let dreamer = try JSONDecoder().decode(PetStage.self, from: Data(#""dreamer""#.utf8))
    try expect(guardian == .ascended, "旧守护形态未迁移到觉醒阶段")
    try expect(dreamer == .ascended, "旧幻光形态未迁移到觉醒阶段")

    let start = Date(timeIntervalSince1970: 10_500)
    var legacyPet = PetSnapshot(now: start)
    legacyPet.stage = guardian
    legacyPet.experience = 75
    PetLifecycleEngine.advance(&legacyPet, to: start.addingTimeInterval(1))
    try expect(legacyPet.stage == .ascended, "迁移后的旧宠物被降级")
}

test("内置十套风格与五个成长阶段") {
    try expect(PetVisualTheme.allCases.count == 10, "建模风格数量不是 10 套")
    try expect(PetStage.allCases.count == 5, "成长阶段数量不是 5 个")
    try expect(Set(PetVisualTheme.allCases.map(\.rawValue)).count == 10, "建模风格标识重复")

    let species = PetVisualTheme.allCases.map(\.speciesAnchor)
    let silhouettes = PetVisualTheme.allCases.map(\.silhouetteAnchor)
    let motions = PetVisualTheme.allCases.map(\.motionAnchor)
    let materials = PetVisualTheme.allCases.map(\.materialAnchor)
    let energies = PetVisualTheme.allCases.map(\.energyAnchor)
    try expect(Set(species).count == 10, "存在重复物种锚点")
    try expect(Set(silhouettes).count == 10, "存在重复轮廓锚点")
    try expect(Set(motions).count == 10, "存在重复运动锚点")
    try expect(Set(materials).count == 10, "存在重复材质锚点")
    try expect(Set(energies).count == 10, "存在重复能量锚点")

    let formNames = PetVisualTheme.allCases.flatMap { theme in
        PetStage.allCases.map { theme.formName(at: $0) }
    }
    try expect(formNames.count == 50, "十套五阶段没有形成 50 个形态")
    try expect(Set(formNames).count == 50, "五十个形态中存在重复命名")
}

test("Codex 事件分类器只读取生命周期状态") {
    let running = #"{"timestamp":"2026-08-07T09:00:00Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-001"}}"#
    let completed = #"{"type":"event_msg","payload":{"type":"task_complete","completed_at":"2026-08-07T09:01:00Z"}}"#
    let failed = #"{"type":"event_msg","payload":{"type":"turn_aborted"}}"#
    let privateMessage = #"{"type":"event_msg","payload":{"type":"user_message","message":"private"}}"#

    try expect(CodexEventClassifier.classify(jsonLine: running)?.activity == .running, "未识别运行状态")
    try expect(CodexEventClassifier.classify(jsonLine: running)?.eventID == "turn-001", "未保留事件去重 ID")
    try expect(CodexEventClassifier.classify(jsonLine: completed)?.activity == .completed, "未识别完成状态")
    try expect(CodexEventClassifier.classify(jsonLine: failed)?.activity == .failed, "未识别失败状态")
    try expect(CodexEventClassifier.classify(jsonLine: privateMessage) == nil, "错误读取了消息正文")
}

test("同一 Codex 轮次不会被重复奖励") {
    let start = Date(timeIntervalSince1970: 11_000)
    var pet = PetSnapshot(now: start)

    let firstApplied = PetLifecycleEngine.apply(
        .completed,
        to: &pet,
        at: start.addingTimeInterval(1),
        eventID: "turn-deduplicate"
    )
    let duplicateApplied = PetLifecycleEngine.apply(
        .completed,
        to: &pet,
        at: start.addingTimeInterval(2),
        eventID: "turn-deduplicate"
    )

    try expect(firstApplied, "首次事件未被处理")
    try expect(!duplicateApplied, "重复事件未被拦截")
    try expect(pet.completedTasks == 1, "重复累计了完成任务")
    try expect(pet.experience == 15, "重复累计了成长经验")
}

test("安装 Codex hooks 时保留用户现有配置") {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let hooksURL = directory.appendingPathComponent("hooks.json")
    let bridgeURL = directory.appendingPathComponent("CainiaoPetBridge")
    let existing: [String: Any] = [
        "hooks": [
            "Stop": [[
                "hooks": [[
                    "type": "command",
                    "command": "/usr/bin/other-hook"
                ]]
            ]]
        ]
    ]
    let data = try JSONSerialization.data(withJSONObject: existing, options: [.prettyPrinted])
    try data.write(to: hooksURL)

    let installer = CodexHooksInstaller()
    try installer.install(at: hooksURL, bridgeExecutable: bridgeURL)
    try expect(installer.isInstalled(at: hooksURL), "hooks 安装状态错误")

    var text = try String(contentsOf: hooksURL, encoding: .utf8)
    try expect(text.contains("/usr/bin/other-hook"), "覆盖了现有 hook")
    try expect(text.contains("CainiaoPetBridge"), "没有写入桌宠 hook")

    try installer.uninstall(at: hooksURL)
    try expect(!installer.isInstalled(at: hooksURL), "hooks 未卸载")

    text = try String(contentsOf: hooksURL, encoding: .utf8)
    try expect(text.contains("/usr/bin/other-hook"), "卸载时删除了现有 hook")
    try expect(!text.contains("CainiaoPetBridge"), "卸载后仍残留桌宠 hook")
}

print("\n全部 \(passed) 项自检通过。")
