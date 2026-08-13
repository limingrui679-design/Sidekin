import SidekinCore
import SidekinCreator
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
    ) else { throw TestFailure(description: "Could not create the mock pet canvas") }
    context.setFillColor(CGColor(red: 1, green: 0, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: side, height: side))
    context.setFillColor(CGColor(red: 0.05, green: 0.55, blue: 1, alpha: 1))
    context.fillEllipse(in: CGRect(x: 55, y: 28, width: 82, height: 132))
    guard let image = context.makeImage() else {
        throw TestFailure(description: "Could not read the mock pet canvas")
    }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else { throw TestFailure(description: "Could not create the mock PNG") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw TestFailure(description: "Could not encode the mock PNG")
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
                throw TestFailure(description: "The mock service has no request handler")
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
                try expect(request.url?.path == "/v1/images/generations", "The text-generation endpoint is incorrect")
                try expect(request.httpMethod == "POST", "Text generation did not use POST")
                try expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key", "The authorization header is incorrect")
                let body = try JSONSerialization.jsonObject(with: bodyData(of: request)) as? [String: Any]
                try expect(body?["model"] as? String == "gpt-image-2", "The text-generation model is incorrect")
                try expect(body?["prompt"] as? String == "original pet", "The text prompt was not included")
                try expect(body?["size"] as? String == "1024x1024", "The generation size is incorrect")
                try expect(body?["quality"] as? String == "medium", "The default generation quality is incorrect")
                return response
            }
            let generated = try await client.generate(prompt: "original pet", apiKey: "test-key")
            try expect(generated == expectedImage, "The text-generation response was not decoded correctly")
            print("✓ Text-generation request and response")

            MockURLProtocol.handler = { request in
                try expect(request.url?.path == "/v1/images/edits", "The reference-edit endpoint is incorrect")
                let contentType = request.value(forHTTPHeaderField: "Content-Type") ?? ""
                try expect(contentType.hasPrefix("multipart/form-data; boundary="), "The edit request is not multipart")
                let body = String(data: bodyData(of: request), encoding: .utf8) ?? ""
                try expect(body.contains("name=\"image[]\""), "The reference image did not use the image[] field")
                try expect(body.contains("filename=\"reference.png\""), "The reference-image filename is missing")
                try expect(body.contains("gpt-image-2"), "The edit model is incorrect")
                try expect(body.contains("faithful lineage"), "The edit prompt was not included")
                try expect(body.contains("medium"), "The edit quality was not included")
                try expect(body.contains("PNGDATA"), "The reference-image data was not written to the request")
                return response
            }
            let edited = try await client.edit(
                prompt: "faithful lineage",
                images: [OpenAIImageInput(data: Data("PNGDATA".utf8), fileName: "reference.png")],
                apiKey: "test-key"
            )
            try expect(edited == expectedImage, "The edit response was not decoded correctly")
            print("✓ Reference-image multipart edit request and response")

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
                templateName: "Mock Growth Line",
                description: "A blue oval test pet",
                artDirection: "Competitive-game character art",
                mode: .text,
                stageNames: ["Egg", "Hatchling", "Apex Form"]
            )
            let template = try await generator.generate(
                request: lineageRequest,
                apiKey: "test-key"
            ) { _, _, _ in }
            try expect(template.stages.count == 3, "The full-line generation stage count is incorrect")
            try expect(
                recorder.snapshot() == [
                    "/v1/images/generations",
                    "/v1/images/edits",
                    "/v1/images/edits"
                ],
                "The full line did not use generation first and edits for later stages"
            )
            let reloaded = try store.load(id: template.id)
            try expect(reloaded?.stages.count == 3, "The generated template was not written to the store")
            for stage in template.stages {
                guard let url = store.assetURL(templateID: template.id, fileName: stage.assetFileName),
                      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
                else { throw TestFailure(description: "A generated stage image could not be read") }
                try expect(image.width == 1_254 && image.height == 1_254, "A generated stage image has the wrong dimensions")
            }
            print("✓ Three-stage generation, transparent processing, and template persistence")

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
                    throw TestFailure(description: "Mock network interruption at stage two")
                }
                return lineageResponse
            }
            let recoveryRequest = PetGenerationRequest(
                templateName: "Resumable Generation",
                description: "A blue oval test pet",
                artDirection: "Competitive-game character art",
                mode: .text,
                quality: .low,
                stageNames: ["Egg", "Hatchling", "Apex Form"]
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
            try expect(didInterrupt, "The mock interruption did not fail generation")
            let interruptedJobs = try recoveryJobStore.loadAll()
            try expect(interruptedJobs.count == 1, "No recovery job remained after interruption")
            let interrupted = interruptedJobs[0]
            try expect(interrupted.completedCount == 1, "The stage completed before interruption was not saved")
            let interruptedRaw = try recoveryJobStore.rawStageData(
                jobID: interrupted.id,
                stageIndex: 0
            )
            try expect(interruptedRaw != nil, "The API image returned before interruption was not saved")

            MockURLProtocol.handler = { request in
                recoveryRecorder.append(request.url?.path ?? "")
                let body = bodyData(of: request)
                try expect(
                    body.range(of: Data("low".utf8)) != nil,
                    "Resumed generation did not preserve Draft quality"
                )
                return lineageResponse
            }
            let recovered = try await recoveryGenerator.resume(
                jobID: interrupted.id,
                apiKey: "test-key"
            ) { _, _, _ in }
            try expect(recovered.stages.count == 3, "The resumed template has the wrong stage count")
            let recoveryPaths = recoveryRecorder.snapshot()
            try expect(
                recoveryPaths.filter { $0 == "/v1/images/generations" }.count == 1,
                "Resumed generation requested the saved first stage again"
            )
            try expect(
                recoveryPaths.filter { $0 == "/v1/images/edits" }.count == 3,
                "The number of edit requests across interruption and resume is incorrect"
            )
            let remainingJobs = try recoveryJobStore.loadAll()
            try expect(remainingJobs.isEmpty, "The recovery job was not removed after completion")
            print("✓ Raw-image retention, resumable generation, and no duplicate paid stage")

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
                templateName: "Keyless Recovery",
                description: "Blue oval test pet",
                artDirection: "Competitive game character",
                mode: .text,
                stageNames: ["Egg", "Juvenile"]
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
                throw TestFailure(description: "Processing a locally recovered raw image must not call the API")
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
                "Local-only recovery did not stop safely before a new request"
            )
            let offlineRecoveredJob = try offlineRecoveryJobStore.load(id: offlineRecoveryJob.id)
            try expect(offlineRecoveredJob.completedCount == 1, "The local raw image was not processed before a key became necessary")
            try expect(offlineRecoveredJob.state == .ready, "Local-only recovery was incorrectly marked as failed")
            try expect(offlineRecoveredJob.lastError == nil, "Local-only recovery left a misleading failure message")
            try expect(offlineRecorder.snapshot().isEmpty, "Keyless recovery unexpectedly made an API request")
            print("✓ A paid raw image can be recovered locally without a key; a key is required only before a new stage request")

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
                name: "Single-Stage Recovery",
                basePrompt: "Blue oval test pet",
                artDirection: "Competitive game character",
                generationMode: .text,
                generationQuality: .high,
                stages: [
                    CustomPetStageDefinition(
                        index: 0,
                        name: "Juvenile",
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
            try expect(firstStageAttemptFailed, "An invalid mock image did not trigger a processing failure")
            try expect(
                stageRecorder.snapshot() == ["/v1/images/generations"],
                "The initial single-stage regeneration request count is incorrect"
            )
            let savedSingleStageRaw = try stageStore.pendingReplacementRaw(
                templateID: singleStageTemplate.id,
                stageIndex: 0
            )
            try expect(savedSingleStageRaw == corruptPaidImage, "The paid single-stage raw image was not persisted first")

            MockURLProtocol.handler = { request in
                stageRecorder.append(request.url?.path ?? "")
                throw TestFailure(description: "Recovery must not request the API again")
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
            try expect(secondStageAttemptFailed, "A corrupted recovered raw image unexpectedly processed successfully")
            try expect(stageRecorder.snapshot().count == 1, "Single-stage recovery created a duplicate paid request")

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
            try expect(repairedStage.resolvedGenerationQuality == .high, "The recovered quality was not written to the template")
            try expect(stageRecorder.snapshot().count == 1, "Using a recovered raw image still called the API")
            let clearedSingleStageRaw = try stageStore.pendingReplacementRaw(
                templateID: singleStageTemplate.id,
                stageIndex: 0
            )
            try expect(clearedSingleStageRaw == nil, "The recovery raw image was not cleared after a successful single-stage replacement")

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
                "Confirmed re-requesting did not create exactly one new paid single-stage request"
            )
            let forceRefreshedRaw = try stageStore.pendingReplacementRaw(
                templateID: singleStageTemplate.id,
                stageIndex: 0
            )
            try expect(forceRefreshedRaw == nil, "The recovery raw image was not cleared after a successful re-request")
            print("✓ A single stage can retry its local raw image for free or make one confirmed new request")

            session.invalidateAndCancel()
            print("\nAll 6 API mock checks passed.")
        } catch {
            fputs("✗ API mock self-test failed: \(error)\n", stderr)
            exit(1)
        }
    }
}
