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
    else { throw TestFailure(description: "Could not create a synthetic test image") }
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

test("A new pet starts in the egg form") {
    let pet = PetSnapshot(now: Date(timeIntervalSince1970: 1_000))
    try expect(pet.stage == .egg, "The initial form is not an egg")
    try expect(pet.experience == 0, "Initial experience is not zero")
    try expect(pet.wellbeing > 70, "Initial wellbeing is too low")
}

test("Feeding restores hunger and triggers hatching") {
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

    try expect(pet.stage == .hatchling, "Three feedings did not unlock First Spark")
    try expect(pet.feedCount == 3, "The feeding count is incorrect")
    try expect(pet.stats.hunger > 90, "Hunger was not restored")
}

test("Completed Codex tasks advance the pet to stage three") {
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

    try expect(pet.experience == 75, "Task experience accumulated incorrectly")
    try expect(pet.stage == .juvenile, "The pet did not reach Shifting Form")
    try expect(pet.completedTasks == 5, "The completed-task count is incorrect")
}

test("Sustained interaction advances the pet to stage four") {
    let start = Date(timeIntervalSince1970: 3_000)
    var pet = PetSnapshot(now: start)

    for offset in 1...20 {
        PetLifecycleEngine.perform(
            .play,
            on: &pet,
            at: start.addingTimeInterval(TimeInterval(offset))
        )
    }

    try expect(pet.experience == 180, "Interaction experience accumulated incorrectly")
    try expect(pet.stage == .ascended, "The pet did not reach Ascension")
    try expect(pet.playCount == 20, "The play count is incorrect")
    try expect(pet.sparkAffinity > pet.careAffinity, "Evolution affinity is incorrect")
}

test("Long-term task completion advances the pet to stage five") {
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

    try expect(pet.experience == 360, "Stage-five experience accumulated incorrectly")
    try expect(pet.stage == .legendary, "The pet did not reach Crown Form")
    try expect(pet.nextStageThreshold == nil, "The final stage still exposes another threshold")
}

test("Sleep restores energy and preserves stat bounds") {
    let start = Date(timeIntervalSince1970: 4_000)
    var pet = PetSnapshot(now: start)
    pet.stats.energy = 30
    pet.isSleeping = true

    PetLifecycleEngine.advance(&pet, to: start.addingTimeInterval(3_600))

    try expect(pet.stats.energy > 45, "Sleep did not restore energy")
    try expect(pet.stats.energy <= 100, "Energy exceeded its maximum")
    try expect(pet.stats.hunger >= 0, "Hunger fell below its minimum")
}

test("The completion animation returns to idle after its display window") {
    let start = Date(timeIntervalSince1970: 5_000)
    var pet = PetSnapshot(now: start)

    PetLifecycleEngine.apply(.completed, to: &pet, at: start.addingTimeInterval(1))
    try expect(pet.codexActivity == .completed, "The pet did not enter the completed state")

    PetLifecycleEngine.advance(&pet, to: start.addingTimeInterval(20))
    try expect(pet.codexActivity == .idle, "The pet did not return to idle after the transient animation")
}

test("Local persistence round-trips without loss") {
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
    try expect(actual == expected, "The loaded save does not match the stored save")
}

test("Legacy wardrobe saves ignore removed fields and migrate safely") {
    let oldWardrobeJSON = #"{"hat":"sprout","face":"none","aura":"sparkles"}"#
    let oldWardrobe = try JSONDecoder().decode(
        PetTemplateSelection.self,
        from: Data(oldWardrobeJSON.utf8)
    )

    try expect(oldWardrobe.theme == nil, "A legacy save should not fabricate a template field")
    try expect(oldWardrobe.customTemplateID == nil, "A legacy wardrobe field was misread as a custom template")
    try expect(oldWardrobe.resolvedTheme == .nova, "The legacy save did not fall back to Nova Arena")
}

test("Custom growth plans support one through eight stages") {
    for count in 1...8 {
        let names = CustomGrowthStagePlan.defaultNames(count: count)
        let thresholds = CustomGrowthStagePlan.thresholds(count: count)
        try expect(names.count == count, "Incorrect stage-name count: \(count)")
        try expect(Set(names).count == count, "Duplicate default stage names: \(count)")
        try expect(thresholds.count == count, "Incorrect stage-threshold count: \(count)")
        try expect(thresholds.first == 0, "The first stage does not start at 0 XP")
        try expect(thresholds == thresholds.sorted(), "Stage thresholds are not increasing")
    }
    try expect(
        CustomGrowthStagePlan.thresholds(count: 5) == [0, 20, 75, 180, 360],
        "The five-stage plan did not preserve the established growth cadence"
    )
}

test("All three quality levels provide current 1024-square output estimates") {
    try expect(
        abs(PetImageGenerationQuality.low.estimatedOutputUSD(stageCount: 5) - 0.030) < 0.000_001,
        "The Draft cost estimate is incorrect"
    )
    try expect(
        abs(PetImageGenerationQuality.medium.estimatedOutputUSD(stageCount: 5) - 0.265) < 0.000_001,
        "The Standard cost estimate is incorrect"
    )
    try expect(
        abs(PetImageGenerationQuality.high.estimatedOutputUSD(stageCount: 5) - 1.055) < 0.000_001,
        "The Final cost estimate is incorrect"
    )
}

test("Custom templates select the correct stage for the current XP") {
    let thresholds = CustomGrowthStagePlan.thresholds(count: 3)
    let template = CustomPetTemplate(
        name: "Three-Stage Companion",
        basePrompt: "Test",
        artDirection: "Test",
        generationMode: .text,
        stages: thresholds.enumerated().map { index, threshold in
            CustomPetStageDefinition(
                index: index,
                name: "Stage \(index + 1)",
                experienceThreshold: threshold,
                assetFileName: "stage-\(index + 1).png"
            )
        }
    )
    try expect(template.stageIndex(for: 0) == 0, "The initial XP stage is incorrect")
    try expect(template.stageIndex(for: thresholds[1] - 1) == 0, "Evolution occurred before the threshold")
    try expect(template.stageIndex(for: thresholds[1]) == 1, "The middle stage did not unlock at its threshold")
    try expect(template.stageIndex(for: thresholds[2]) == 2, "The final stage did not unlock at its threshold")
}

test("Custom templates are written atomically and read without loss") {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let stages = CustomGrowthStagePlan.thresholds(count: 3).enumerated().map { index, threshold in
        CustomPetStageDefinition(
            index: index,
            name: "Stage \(index + 1)",
            experienceThreshold: threshold,
            assetFileName: String(format: "stage-%02d.png", index + 1)
        )
    }
    let template = CustomPetTemplate(
        name: "Test Companion",
        basePrompt: "A test creature",
        artDirection: "Competitive-game character art",
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
    try expect(loaded == template, "The loaded template manifest does not match")
    let allTemplates = try store.loadAll()
    try expect(allTemplates == [template], "The template list does not match")
    let secondURL = store.assetURL(templateID: template.id, fileName: "stage-02.png")
    try expect(secondURL != nil, "The second-stage asset is missing")
    let secondData = try Data(contentsOf: secondURL!)
    try expect(secondData == images[1], "The stage-image data does not match")
}

test("The template store rejects path-traversal filenames") {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let template = CustomPetTemplate(
        name: "Invalid Template",
        basePrompt: "Test",
        artDirection: "Test",
        generationMode: .text,
        stages: [
            CustomPetStageDefinition(
                index: 0,
                name: "Stage 1",
                experienceThreshold: 0,
                assetFileName: "../escape.png"
            )
        ]
    )
    let store = PetTemplateStore(templatesDirectory: directory)
    do {
        try store.install(template: template, stageImages: [Data([1])])
        throw TestFailure(description: "The template store accepted an unsafe asset path")
    } catch PetTemplateStoreError.invalidStageLayout {
        // Expected.
    }
}

test("Templates support rename, stage replacement, export, import, and deletion") {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PetTemplateStore(templatesDirectory: directory)
    let template = CustomPetTemplate(
        name: "Managed Template",
        basePrompt: "Test",
        artDirection: "Test",
        generationMode: .faithful,
        generationQuality: .low,
        referenceFileName: "reference.png",
        stages: [
            CustomPetStageDefinition(
                index: 0,
                name: "Hatchling",
                experienceThreshold: 0,
                assetFileName: "stage-01.png"
            ),
            CustomPetStageDefinition(
                index: 1,
                name: "Adult",
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
    let renamed = try store.rename(id: template.id, to: "Renamed Template")
    try expect(renamed.name == "Renamed Template", "The renamed template was not persisted")

    let replaced = try store.replaceStageImage(
        templateID: template.id,
        stageIndex: 1,
        imageData: replacementStage,
        prompt: "replacement",
        generationQuality: .high
    )
    try expect(replaced.stages[1].prompt == "replacement", "The replacement stage prompt was not updated")
    try expect(replaced.resolvedGenerationQuality == .high, "The replacement quality was not updated")
    let replacedData = try store.assetData(templateID: template.id, fileName: "stage-02.png")
    try expect(replacedData == replacementStage, "The stage image was not replaced in place")

    let package = try store.exportPackage(id: template.id)
    let imported = try store.importPackage(package)
    try expect(imported.id != template.id, "Repeated import did not create a safe new identifier")
    try expect(imported.name == renamed.name, "The imported template name does not match")
    let importedReference = try store.referenceData(template: imported)
    try expect(importedReference == referenceImage, "The imported reference image does not match")
    let importedTemplates = try store.loadAll()
    try expect(importedTemplates.count == 2, "The imported template was not added to the library")

    var corruptPackage = package
    let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    guard let signatureRange = corruptPackage.range(of: pngSignature) else {
        throw TestFailure(description: "The test template package contains no PNG data")
    }
    corruptPackage.replaceSubrange(
        signatureRange,
        with: Data(repeating: 0, count: pngSignature.count)
    )
    do {
        _ = try store.importPackage(corruptPackage)
        throw TestFailure(description: "A template package with a damaged image was imported")
    } catch PetTemplateStoreError.invalidPackage {
        // Expected.
    }

    try store.remove(id: template.id)
    let deletedTemplate = try store.load(id: template.id)
    try expect(deletedTemplate == nil, "The template still exists after deletion")
}

test("The template store rejects invalid images disguised as PNG files") {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PetTemplateStore(templatesDirectory: directory)
    let template = CustomPetTemplate(
        name: "Invalid Image Test",
        basePrompt: "Test",
        artDirection: "Test",
        generationMode: .text,
        stages: [
            CustomPetStageDefinition(
                index: 0,
                name: "Hatchling",
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
        throw TestFailure(description: "The template store accepted an invalid image")
    } catch PetTemplateStoreError.invalidImage {
        // Expected.
    }
}

test("Generation recovery saves paid images first and supports stage restarts") {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PetGenerationJobStore(jobsDirectory: directory)
    let request = PetGenerationRequest(
        templateName: "Recovery Test",
        description: "A test pet",
        artDirection: "Competitive-game character art",
        mode: .text,
        quality: .low,
        stageNames: ["Egg", "Hatchling", "Adult"]
    )
    var job = try store.create(request: request, normalizedReference: nil)
    let paidRaw = Data("paid-api-result".utf8)
    try store.saveRawStage(jobID: job.id, stageIndex: 0, data: paidRaw)
    job = try store.load(id: job.id)
    try expect(job.completedCount == 0, "A raw image alone must not mark the stage complete")
    let recoveredRaw = try store.rawStageData(jobID: job.id, stageIndex: 0)
    try expect(recoveredRaw == paidRaw, "The API image was not saved before processing")
    try expect(store.rawStageURL(jobID: job.id, stageIndex: 0) != nil, "The API-image preview is missing")

    let definition = CustomPetStageDefinition(
        index: 0,
        name: "Egg",
        prompt: "stage prompt",
        experienceThreshold: 0,
        assetFileName: "stage-01.png"
    )
    job = try store.saveProcessedStage(
        jobID: job.id,
        definition: definition,
        data: Data("transparent-preview".utf8)
    )
    try expect(job.completedCount == 1, "The checkpoint did not advance after processing")
    try expect(store.processedStageURL(jobID: job.id, stageIndex: 0) != nil, "The cutout preview is missing")
    _ = try store.updateState(jobID: job.id, state: .failed, errorMessage: "mock failure")
    let failedJob = try store.load(id: job.id)
    try expect(failedJob.lastError == "mock failure", "The failure reason was not persisted")

    job = try store.restart(jobID: job.id, fromStage: 0)
    try expect(job.completedCount == 0, "Restarting from a stage did not clear later checkpoints")
    let restartedRaw = try store.rawStageData(jobID: job.id, stageIndex: 0)
    try expect(restartedRaw == nil, "The previous raw image remains after restart")

    try store.saveRawStage(jobID: job.id, stageIndex: 1, data: paidRaw)
    try expect(store.rawStageURL(jobID: job.id, stageIndex: 1) != nil, "The current failed-stage image was not saved")
    job = try store.restart(jobID: job.id, fromStage: 1)
    let clearedCurrentRaw = try store.rawStageData(jobID: job.id, stageIndex: 1)
    try expect(clearedCurrentRaw == nil, "The cleared failed stage would still reuse its old image")
}

test("Paid single-stage regeneration also preserves a raw-image checkpoint") {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PetTemplateStore(templatesDirectory: directory)
    let template = CustomPetTemplate(
        name: "Single-Stage Recovery Test",
        basePrompt: "Test",
        artDirection: "Competitive-game character art",
        generationMode: .text,
        stages: [
            CustomPetStageDefinition(
                index: 0,
                name: "Hatchling",
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
    try expect(
        store.hasPendingReplacementRaw(templateID: template.id, stageIndex: 0),
        "The UI cannot detect the saved single-stage image"
    )
    let savedRaw = try store.pendingReplacementRaw(templateID: template.id, stageIndex: 0)
    try expect(savedRaw == paidRaw, "The paid single-stage image was not persisted")
    try store.clearPendingReplacementRaw(templateID: template.id, stageIndex: 0)
    let clearedRaw = try store.pendingReplacementRaw(templateID: template.id, stageIndex: 0)
    try expect(clearedRaw == nil, "The recovery checkpoint was not cleared after stage replacement")
    try expect(
        !store.hasPendingReplacementRaw(templateID: template.id, stageIndex: 0),
        "The UI still reports a saved single-stage image after cleanup"
    )
}

test("Generation prompts enforce structural stage changes and a solid cutout background") {
    let request = PetGenerationRequest(
        templateName: "Eclipse Companion",
        description: "A feline creature with moon markings",
        artDirection: "Competitive-game 3D character art",
        mode: .faithful,
        stageNames: CustomGrowthStagePlan.defaultNames(count: 5),
        referenceImage: Data([1])
    )
    let prompt = PetLineageGenerator.prompt(
        request: request,
        stageIndex: 3,
        stageName: request.stageNames[3]
    )
    try expect(prompt.contains("genuinely different body proportion"), "The prompt does not require structural stage differences")
    try expect(prompt.contains("#FF00FF"), "The prompt does not require a solid cutout background")
    try expect(prompt.contains(request.artDirection), "The user's art direction was not included")
    try expect(prompt.contains("Preserve the uploaded subject's identity"), "High-fidelity mode does not preserve subject identity")
}

test("Generated images are normalized into transparent 1254-square assets") {
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
    else { throw TestFailure(description: "Could not create the synthetic test image") }

    let output = try PetImageProcessor.prepareGeneratedAsset(sourcePNG)
    guard let outputRep = NSBitmapImageRep(data: output) else {
        throw TestFailure(description: "The processed result is not a valid image")
    }
    try expect(outputRep.pixelsWide == 1_254, "The output width is not 1254")
    try expect(outputRep.pixelsHigh == 1_254, "The output height is not 1254")
    try expect((outputRep.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.05, "The output corner is not transparent")
    try expect((outputRep.colorAt(x: 627, y: 627)?.alphaComponent ?? 0) > 0.8, "The pet subject was removed incorrectly")
}

test("Edge-connected cutout preserves magenta and purple inside the subject") {
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
        throw TestFailure(description: "Could not read the edge-connected cutout output")
    }
    try expect((rep.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.05, "The edge-connected magenta background was not removed")
    try expect((rep.colorAt(x: 627, y: 627)?.alphaComponent ?? 0) > 0.8, "Magenta inside the subject was removed incorrectly")
}

test("Cutout adaptively detects non-magenta solid backgrounds from canvas edges") {
    let sourcePNG = try makePNG {
        NSColor(calibratedRed: 0.02, green: 0.82, blue: 0.88, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 160, height: 160)).fill()
        NSColor.systemPink.setFill()
        NSBezierPath(ovalIn: NSRect(x: 42, y: 25, width: 76, height: 110)).fill()
    }
    let output = try PetImageProcessor.prepareGeneratedAsset(sourcePNG)
    guard let rep = NSBitmapImageRep(data: output) else {
        throw TestFailure(description: "Could not read the adaptive cutout output")
    }
    try expect((rep.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.05, "The adaptive background did not become transparent")
    try expect((rep.colorAt(x: 627, y: 627)?.alphaComponent ?? 0) > 0.8, "The pink subject was damaged by adaptive background removal")
}

test("Both legacy final evolutions migrate safely to stage four") {
    let guardian = try JSONDecoder().decode(PetStage.self, from: Data(#""guardian""#.utf8))
    let dreamer = try JSONDecoder().decode(PetStage.self, from: Data(#""dreamer""#.utf8))
    try expect(guardian == .ascended, "The legacy guardian form did not migrate to Ascension")
    try expect(dreamer == .ascended, "The legacy dreamer form did not migrate to Ascension")

    let start = Date(timeIntervalSince1970: 10_500)
    var legacyPet = PetSnapshot(now: start)
    legacyPet.stage = guardian
    legacyPet.experience = 75
    PetLifecycleEngine.advance(&legacyPet, to: start.addingTimeInterval(1))
    try expect(legacyPet.stage == .ascended, "The migrated legacy pet was downgraded")
}

test("The app includes ten themes and five growth stages") {
    try expect(PetVisualTheme.allCases.count == 10, "The theme count is not 10")
    try expect(PetStage.allCases.count == 5, "The growth-stage count is not 5")
    try expect(Set(PetVisualTheme.allCases.map(\.rawValue)).count == 10, "Theme identifiers are duplicated")

    let species = PetVisualTheme.allCases.map(\.speciesAnchor)
    let silhouettes = PetVisualTheme.allCases.map(\.silhouetteAnchor)
    let motions = PetVisualTheme.allCases.map(\.motionAnchor)
    let materials = PetVisualTheme.allCases.map(\.materialAnchor)
    let energies = PetVisualTheme.allCases.map(\.energyAnchor)
    try expect(Set(species).count == 10, "Species anchors are duplicated")
    try expect(Set(silhouettes).count == 10, "Silhouette anchors are duplicated")
    try expect(Set(motions).count == 10, "Movement anchors are duplicated")
    try expect(Set(materials).count == 10, "Material anchors are duplicated")
    try expect(Set(energies).count == 10, "Energy anchors are duplicated")

    let formNames = PetVisualTheme.allCases.flatMap { theme in
        PetStage.allCases.map { theme.formName(at: $0) }
    }
    try expect(formNames.count == 50, "Ten five-stage lines did not produce 50 forms")
    try expect(Set(formNames).count == 50, "The 50 forms contain duplicate names")
}

test("The Codex event classifier reads lifecycle state only") {
    let running = #"{"timestamp":"2026-08-07T09:00:00Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-001"}}"#
    let completed = #"{"type":"event_msg","payload":{"type":"task_complete","completed_at":"2026-08-07T09:01:00Z"}}"#
    let failed = #"{"type":"event_msg","payload":{"type":"turn_aborted"}}"#
    let privateMessage = #"{"type":"event_msg","payload":{"type":"user_message","message":"private"}}"#

    try expect(CodexEventClassifier.classify(jsonLine: running)?.activity == .running, "The running state was not recognized")
    try expect(CodexEventClassifier.classify(jsonLine: running)?.eventID == "turn-001", "The deduplication event ID was not preserved")
    try expect(CodexEventClassifier.classify(jsonLine: completed)?.activity == .completed, "The completed state was not recognized")
    try expect(CodexEventClassifier.classify(jsonLine: failed)?.activity == .failed, "The failed state was not recognized")
    try expect(CodexEventClassifier.classify(jsonLine: privateMessage) == nil, "Private message content was read incorrectly")
}

test("The same Codex turn is never rewarded twice") {
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

    try expect(firstApplied, "The first event was not processed")
    try expect(!duplicateApplied, "The duplicate event was not blocked")
    try expect(pet.completedTasks == 1, "Completed tasks were counted twice")
    try expect(pet.experience == 15, "Growth experience was counted twice")
}

test("Installing Codex hooks preserves the user's existing configuration") {
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
    try expect(installer.isInstalled(at: hooksURL), "The hooks installation state is incorrect")

    var text = try String(contentsOf: hooksURL, encoding: .utf8)
    try expect(text.contains("/usr/bin/other-hook"), "An existing hook was overwritten")
    try expect(text.contains("CainiaoPetBridge"), "The CainiaoPet hook was not written")

    try installer.uninstall(at: hooksURL)
    try expect(!installer.isInstalled(at: hooksURL), "The hooks were not uninstalled")

    text = try String(contentsOf: hooksURL, encoding: .utf8)
    try expect(text.contains("/usr/bin/other-hook"), "Uninstallation deleted an existing hook")
    try expect(!text.contains("CainiaoPetBridge"), "The CainiaoPet hook remains after uninstallation")
}

print("\nAll \(passed) local checks passed.")
