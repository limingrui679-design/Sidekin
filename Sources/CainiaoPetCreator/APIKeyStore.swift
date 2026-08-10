import Foundation
import Security

public enum APIKeyStoreError: LocalizedError {
    case invalidKey
    case keychain(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .invalidKey:
            "The API key cannot be empty."
        case let .keychain(status):
            (SecCopyErrorMessageString(status, nil) as String?)
                ?? "The Keychain operation failed (\(status))."
        }
    }
}

public struct OpenAIAPIKeyStore: Sendable {
    public let service: String
    public let account: String

    public init(
        service: String = "local.cainiao.codexpet.openai",
        account: String = "image-api-key"
    ) {
        self.service = service
        self.account = account
    }

    public func hasKey() -> Bool {
        (try? read()) != nil
    }

    public func read() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw APIKeyStoreError.keychain(status) }
        guard let data = result as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else {
            throw APIKeyStoreError.invalidKey
        }
        return key
    }

    public func save(_ rawKey: String) throws {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw APIKeyStoreError.invalidKey }
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw APIKeyStoreError.keychain(updateStatus)
        }

        var insertion = query
        insertion.merge(attributes) { _, new in new }
        let addStatus = SecItemAdd(insertion as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw APIKeyStoreError.keychain(addStatus)
        }
    }

    public func remove() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw APIKeyStoreError.keychain(status)
        }
    }
}
