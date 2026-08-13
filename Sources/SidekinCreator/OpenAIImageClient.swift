import Foundation

public struct OpenAIImageInput: Sendable {
    public let data: Data
    public let fileName: String
    public let mimeType: String

    public init(data: Data, fileName: String, mimeType: String = "image/png") {
        self.data = data
        self.fileName = fileName
        self.mimeType = mimeType
    }
}

public enum OpenAIImageClientError: LocalizedError {
    case invalidResponse
    case http(status: Int, message: String, requestID: String?)
    case missingImage
    case invalidBase64

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The image service returned an unrecognized response."
        case let .http(status, message, requestID):
            ["The image-service request failed (HTTP \(status)): \(message)", requestID.map { "Request ID: \($0)" }]
                .compactMap { $0 }
                .joined(separator: "\n")
        case .missingImage:
            "The image service did not return an image."
        case .invalidBase64:
            "The image data returned by the service is damaged."
        }
    }
}

public actor OpenAIImageClient {
    private let session: URLSession
    private let baseURL: URL

    public init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://api.openai.com/v1")!
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    public func generate(
        prompt: String,
        apiKey: String,
        size: String = "1024x1024",
        quality: String = "medium"
    ) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent("images/generations"))
        request.httpMethod = "POST"
        request.timeoutInterval = 240
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "gpt-image-2",
            "prompt": prompt,
            "size": size,
            "quality": quality,
            "n": 1
        ])
        return try await perform(request)
    }

    public func edit(
        prompt: String,
        images: [OpenAIImageInput],
        apiKey: String,
        size: String = "1024x1024",
        quality: String = "medium"
    ) async throws -> Data {
        guard !images.isEmpty else { throw OpenAIImageClientError.missingImage }
        let boundary = "Sidekin-\(UUID().uuidString)"
        var request = URLRequest(url: baseURL.appendingPathComponent("images/edits"))
        request.httpMethod = "POST"
        request.timeoutInterval = 240
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(
            boundary: boundary,
            fields: [
                ("model", "gpt-image-2"),
                ("prompt", prompt),
                ("size", size),
                ("quality", quality)
            ],
            images: images
        )
        return try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIImageClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
            let message = envelope?.error.message
                ?? String(data: data, encoding: .utf8)
                ?? "Unknown error"
            throw OpenAIImageClientError.http(
                status: http.statusCode,
                message: message,
                requestID: http.value(forHTTPHeaderField: "x-request-id")
            )
        }

        guard let decoded = try? JSONDecoder().decode(ImageResponse.self, from: data) else {
            throw OpenAIImageClientError.invalidResponse
        }
        guard let encoded = decoded.data.first?.b64JSON else {
            throw OpenAIImageClientError.missingImage
        }
        guard let image = Data(base64Encoded: encoded) else {
            throw OpenAIImageClientError.invalidBase64
        }
        return image
    }

    private static func multipartBody(
        boundary: String,
        fields: [(String, String)],
        images: [OpenAIImageInput]
    ) -> Data {
        var body = Data()
        func append(_ string: String) {
            body.append(Data(string.utf8))
        }

        for (name, value) in fields {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }
        for image in images {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"image[]\"; filename=\"\(image.fileName)\"\r\n")
            append("Content-Type: \(image.mimeType)\r\n\r\n")
            body.append(image.data)
            append("\r\n")
        }
        append("--\(boundary)--\r\n")
        return body
    }
}

private struct ImageResponse: Decodable {
    struct Item: Decodable {
        let b64JSON: String?

        enum CodingKeys: String, CodingKey {
            case b64JSON = "b64_json"
        }
    }

    let data: [Item]
}

private struct APIErrorEnvelope: Decodable {
    struct APIError: Decodable { let message: String }
    let error: APIError
}
