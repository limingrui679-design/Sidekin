import CainiaoPetCore
import CainiaoPetCreator
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw TestFailure(description: message) }
}

private func bodyData(of request: URLRequest) -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var output = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        guard count > 0 else { break }
        output.append(buffer, count: count)
    }
    return output
}

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [String] = []

    func append(_ path: String) {
        lock.lock()
        paths.append(path)
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return paths
    }
}

private func syntheticPetPNG() throws -> Data {
    let side = 192
    guard let context = CGContext(
        data: nil,
        width: side,
        height: side,
        bitsPerComponent: 8,
        bytesPerRow: side * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw TestFailure(description: "无法创建模拟宠物画布") }
    context.setFillColor(CGColor(red: 1, green: 0, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: side, height: side))
    context.setFillColor(CGColor(red: 0.05, green: 0.55, blue: 1, alpha: 1))
    context.fillEllipse(in: CGRect(x: 55, y: 28, width: 82, height: 132))
    guard let image = context.makeImage() else {
        throw TestFailure(description: "无法读取模拟宠物画布")
    }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else { throw TestFailure(description: "无法创建模拟 PNG") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw TestFailure(description: "无法编码模拟 PNG")
    }
    return data as Data
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> Data)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler else {
                throw TestFailure(description: "模拟服务没有处理器")
            }
            let data = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@main
private struct APISelfTestRunner {
    static func main() async {
        do {
            let expectedImage = Data("mock-image".utf8)
            let response = try JSONSerialization.data(withJSONObject: [
                "data": [["b64_json": expectedImage.base64EncodedString()]]
            ])
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [MockURLProtocol.self]
            let session = URLSession(configuration: configuration)
            let client = OpenAIImageClient(
                session: session,
                baseURL: URL(string: "https://unit.test/v1")!
            )

            MockURLProtocol.handler = { request in
                try expect(request.url?.path == "/v1/images/generations", "文字生成端点错误")
                try expect(request.httpMethod == "POST", "文字生成不是 POST")
                try expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key", "鉴权头错误")
                let body = try JSONSerialization.jsonObject(with: bodyData(of: request)) as? [String: Any]
                try expect(body?["model"] as? String == "gpt-image-2", "文字生成模型错误")
                try expect(body?["prompt"] as? String == "original pet", "文字提示没有传入")
                try expect(body?["size"] as? String == "1024x1024", "生成尺寸错误")
                try expect(body?["quality"] as? String == "medium", "默认生成质量错误")
                return response
            }
            let generated = try await client.generate(prompt: "original pet", apiKey: "test-key")
            try expect(generated == expectedImage, "文字生成响应没有正确解码")
            print("✓ 文字生成请求与响应")

            MockURLProtocol.handler = { request in
                try expect(request.url?.path == "/v1/images/edits", "参考图编辑端点错误")
                let contentType = request.value(forHTTPHeaderField: "Content-Type") ?? ""
                try expect(contentType.hasPrefix("multipart/form-data; boundary="), "编辑请求不是 multipart")
                let body = String(data: bodyData(of: request), encoding: .utf8) ?? ""
                try expect(body.contains("name=\"image[]\""), "参考图没有使用 image[] 字段")
                try expect(body.contains("filename=\"reference.png\""), "参考图文件名丢失")
                try expect(body.contains("gpt-image-2"), "编辑模型错误")
                try expect(body.contains("faithful lineage"), "编辑提示没有传入")
                try expect(body.contains("medium"), "编辑质量没有传入")
                try expect(body.contains("PNGDATA"), "参考图二进制没有写入请求")
                return response
            }
            let edited = try await client.edit(
                prompt: "faithful lineage",
                images: [OpenAIImageInput(data: Data("PNGDATA".utf8), fileName: "reference.png")],
                apiKey: "test-key"
            )
            try expect(edited == expectedImage, "编辑响应没有正确解码")
            print("✓ 参考图编辑 multipart 请求与响应")

            let temporaryDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
            let mockPet = try syntheticPetPNG()
            let lineageResponse = try JSONSerialization.data(withJSONObject: [
                "data": [["b64_json": mockPet.base64EncodedString()]]
            ])
            let recorder = RequestRecorder()
            MockURLProtocol.handler = { request in
                recorder.append(request.url?.path ?? "")
                return lineageResponse
            }
            let store = PetTemplateStore(
                templatesDirectory: temporaryDirectory.appendingPathComponent("templates")
            )
            let jobStore = PetGenerationJobStore(
                jobsDirectory: temporaryDirectory.appendingPathComponent("jobs")
            )
            let generator = PetLineageGenerator(
                client: client,
                store: store,
                jobStore: jobStore
            )
            let lineageRequest = PetGenerationRequest(
                templateName: "模拟成长线",
                description: "蓝色椭圆测试宠物",
                artDirection: "竞技游戏角色",
                mode: .text,
                stageNames: ["蛋", "幼体", "终极体"]
            )
            let template = try await generator.generate(
                request: lineageRequest,
                apiKey: "test-key"
            ) { _, _, _ in }
            try expect(template.stages.count == 3, "整链生成阶段数错误")
            try expect(
                recorder.snapshot() == [
                    "/v1/images/generations",
                    "/v1/images/edits",
                    "/v1/images/edits"
                ],
                "整链生成没有按首图原创、后续编辑执行"
            )
            let reloaded = try store.load(id: template.id)
            try expect(reloaded?.stages.count == 3, "生成模板没有写入仓库")
            for stage in template.stages {
                guard let url = store.assetURL(templateID: template.id, fileName: stage.assetFileName),
                      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
                else { throw TestFailure(description: "生成阶段图片无法读取") }
                try expect(image.width == 1_254 && image.height == 1_254, "生成阶段图片尺寸错误")
            }
            print("✓ 三阶段生成、透明处理与模板落盘整链")

            let recoveryDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: recoveryDirectory) }
            let recoveryStore = PetTemplateStore(
                templatesDirectory: recoveryDirectory.appendingPathComponent("templates")
            )
            let recoveryJobStore = PetGenerationJobStore(
                jobsDirectory: recoveryDirectory.appendingPathComponent("jobs")
            )
            let recoveryGenerator = PetLineageGenerator(
                client: client,
                store: recoveryStore,
                jobStore: recoveryJobStore
            )
            let recoveryRecorder = RequestRecorder()
            MockURLProtocol.handler = { request in
                recoveryRecorder.append(request.url?.path ?? "")
                if recoveryRecorder.snapshot().count == 2 {
                    throw TestFailure(description: "模拟第二阶段网络中断")
                }
                return lineageResponse
            }
            let recoveryRequest = PetGenerationRequest(
                templateName: "断点续跑",
                description: "蓝色椭圆测试宠物",
                artDirection: "竞技游戏角色",
                mode: .text,
                quality: .low,
                stageNames: ["蛋", "幼体", "终极体"]
            )
            var didInterrupt = false
            do {
                _ = try await recoveryGenerator.generate(
                    request: recoveryRequest,
                    apiKey: "test-key"
                ) { _, _, _ in }
            } catch {
                didInterrupt = true
            }
            try expect(didInterrupt, "模拟中断没有使生成失败")
            let interruptedJobs = try recoveryJobStore.loadAll()
            try expect(interruptedJobs.count == 1, "中断后没有保留恢复任务")
            let interrupted = interruptedJobs[0]
            try expect(interrupted.completedCount == 1, "中断前完成阶段没有保存")
            let interruptedRaw = try recoveryJobStore.rawStageData(
                jobID: interrupted.id,
                stageIndex: 0
            )
            try expect(interruptedRaw != nil, "中断前 API 原图没有保存")

            MockURLProtocol.handler = { request in
                recoveryRecorder.append(request.url?.path ?? "")
                let body = bodyData(of: request)
                try expect(
                    body.range(of: Data("low".utf8)) != nil,
                    "续跑没有保留草稿质量"
                )
                return lineageResponse
            }
            let recovered = try await recoveryGenerator.resume(
                jobID: interrupted.id,
                apiKey: "test-key"
            ) { _, _, _ in }
            try expect(recovered.stages.count == 3, "续跑完成后的阶段数错误")
            let recoveryPaths = recoveryRecorder.snapshot()
            try expect(
                recoveryPaths.filter { $0 == "/v1/images/generations" }.count == 1,
                "续跑重复请求了已保存的第一阶段"
            )
            try expect(
                recoveryPaths.filter { $0 == "/v1/images/edits" }.count == 3,
                "中断和续跑的编辑请求数量错误"
            )
            let remainingJobs = try recoveryJobStore.loadAll()
            try expect(remainingJobs.isEmpty, "续跑完成后恢复任务没有清理")
            print("✓ 失败后保留原图、断点续跑且不重复计费阶段")

            let offlineRecoveryDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: offlineRecoveryDirectory) }
            let offlineRecoveryStore = PetTemplateStore(
                templatesDirectory: offlineRecoveryDirectory.appendingPathComponent("templates")
            )
            let offlineRecoveryJobStore = PetGenerationJobStore(
                jobsDirectory: offlineRecoveryDirectory.appendingPathComponent("jobs")
            )
            let offlineRecoveryGenerator = PetLineageGenerator(
                client: client,
                store: offlineRecoveryStore,
                jobStore: offlineRecoveryJobStore
            )
            let offlineRecoveryRequest = PetGenerationRequest(
                templateName: "无 Key 恢复",
                description: "蓝色椭圆测试宠物",
                artDirection: "竞技游戏角色",
                mode: .text,
                stageNames: ["蛋", "幼体"]
            )
            let offlineRecoveryJob = try offlineRecoveryJobStore.create(
                request: offlineRecoveryRequest,
                normalizedReference: nil
            )
            try offlineRecoveryJobStore.saveRawStage(
                jobID: offlineRecoveryJob.id,
                stageIndex: 0,
                data: mockPet
            )
            let offlineRecorder = RequestRecorder()
            MockURLProtocol.handler = { request in
                offlineRecorder.append(request.url?.path ?? "")
                throw TestFailure(description: "处理本机恢复原图时不应请求 API")
            }
            var offlineResumeStoppedBeforeNewRequest = false
            do {
                _ = try await offlineRecoveryGenerator.resume(
                    jobID: offlineRecoveryJob.id,
                    apiKey: nil,
                    allowNewRequests: false
                ) { _, _, _ in }
            } catch PetLineageGeneratorError.newRequestRequired {
                offlineResumeStoppedBeforeNewRequest = true
            }
            try expect(
                offlineResumeStoppedBeforeNewRequest,
                "仅本机恢复没有在新请求前安全停止"
            )
            let offlineRecoveredJob = try offlineRecoveryJobStore.load(id: offlineRecoveryJob.id)
            try expect(offlineRecoveredJob.completedCount == 1, "无 Key 时没有先完成本机原图处理")
            try expect(offlineRecoveredJob.state == .ready, "仅本机恢复被错误标记为失败")
            try expect(offlineRecoveredJob.lastError == nil, "仅本机恢复留下了误导性的失败信息")
            try expect(offlineRecorder.snapshot().isEmpty, "无 Key 恢复意外发起了 API 请求")
            print("✓ 已付费本机原图可无 Key 免费恢复，新增阶段前才要求 Key")

            let stageDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: stageDirectory) }
            let stageStore = PetTemplateStore(
                templatesDirectory: stageDirectory.appendingPathComponent("templates")
            )
            let stageJobStore = PetGenerationJobStore(
                jobsDirectory: stageDirectory.appendingPathComponent("jobs")
            )
            let stageGenerator = PetLineageGenerator(
                client: client,
                store: stageStore,
                jobStore: stageJobStore
            )
            let singleStageTemplate = CustomPetTemplate(
                name: "单阶段恢复",
                basePrompt: "蓝色椭圆测试宠物",
                artDirection: "竞技游戏角色",
                generationMode: .text,
                generationQuality: .high,
                stages: [
                    CustomPetStageDefinition(
                        index: 0,
                        name: "幼体",
                        experienceThreshold: 0,
                        assetFileName: "stage-01.png"
                    )
                ]
            )
            try stageStore.install(
                template: singleStageTemplate,
                stageImages: [mockPet]
            )
            let corruptPaidImage = Data("paid-but-corrupt-image".utf8)
            let corruptResponse = try JSONSerialization.data(withJSONObject: [
                "data": [["b64_json": corruptPaidImage.base64EncodedString()]]
            ])
            let stageRecorder = RequestRecorder()
            MockURLProtocol.handler = { request in
                stageRecorder.append(request.url?.path ?? "")
                return corruptResponse
            }
            var firstStageAttemptFailed = false
            do {
                _ = try await stageGenerator.regenerateStage(
                    templateID: singleStageTemplate.id,
                    stageIndex: 0,
                    quality: .high,
                    apiKey: "test-key"
                )
            } catch {
                firstStageAttemptFailed = true
            }
            try expect(firstStageAttemptFailed, "无效模拟图片没有触发处理失败")
            try expect(
                stageRecorder.snapshot() == ["/v1/images/generations"],
                "单阶段首次重绘请求数量错误"
            )
            let savedSingleStageRaw = try stageStore.pendingReplacementRaw(
                templateID: singleStageTemplate.id,
                stageIndex: 0
            )
            try expect(savedSingleStageRaw == corruptPaidImage, "单阶段付费原图没有先落盘")

            MockURLProtocol.handler = { request in
                stageRecorder.append(request.url?.path ?? "")
                throw TestFailure(description: "恢复时不应再次请求 API")
            }
            var secondStageAttemptFailed = false
            do {
                _ = try await stageGenerator.regenerateStage(
                    templateID: singleStageTemplate.id,
                    stageIndex: 0,
                    quality: .high,
                    apiKey: nil
                )
            } catch {
                secondStageAttemptFailed = true
            }
            try expect(secondStageAttemptFailed, "损坏恢复原图意外处理成功")
            try expect(stageRecorder.snapshot().count == 1, "单阶段恢复重复产生了付费请求")

            try stageStore.savePendingReplacementRaw(
                templateID: singleStageTemplate.id,
                stageIndex: 0,
                data: mockPet
            )
            let repairedStage = try await stageGenerator.regenerateStage(
                templateID: singleStageTemplate.id,
                stageIndex: 0,
                quality: .high,
                apiKey: nil
            )
            try expect(repairedStage.resolvedGenerationQuality == .high, "恢复后质量没有写入模板")
            try expect(stageRecorder.snapshot().count == 1, "使用恢复原图时仍调用了 API")
            let clearedSingleStageRaw = try stageStore.pendingReplacementRaw(
                templateID: singleStageTemplate.id,
                stageIndex: 0
            )
            try expect(clearedSingleStageRaw == nil, "单阶段替换成功后恢复原图没有清理")

            try stageStore.savePendingReplacementRaw(
                templateID: singleStageTemplate.id,
                stageIndex: 0,
                data: corruptPaidImage
            )
            MockURLProtocol.handler = { request in
                stageRecorder.append(request.url?.path ?? "")
                return lineageResponse
            }
            _ = try await stageGenerator.regenerateStage(
                templateID: singleStageTemplate.id,
                stageIndex: 0,
                quality: .high,
                apiKey: "test-key",
                forceNewRequest: true
            )
            try expect(
                stageRecorder.snapshot() == [
                    "/v1/images/generations",
                    "/v1/images/generations"
                ],
                "确认重新请求没有准确产生一次新的单阶段费用请求"
            )
            let forceRefreshedRaw = try stageStore.pendingReplacementRaw(
                templateID: singleStageTemplate.id,
                stageIndex: 0
            )
            try expect(forceRefreshedRaw == nil, "重新请求成功后恢复原图没有清理")
            print("✓ 单阶段可免费重试本机原图，也可确认后重新请求一次")

            session.invalidateAndCancel()
            print("\n全部 6 项 API 模拟自检通过。")
        } catch {
            fputs("✗ API 模拟自检失败：\(error)\n", stderr)
            exit(1)
        }
    }
}
