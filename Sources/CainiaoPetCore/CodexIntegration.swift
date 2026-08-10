import Foundation

public struct CodexActivityRecord: Equatable, Sendable {
    public let activity: CodexActivity
    public let timestamp: Date?
    public let eventID: String?

    public init(activity: CodexActivity, timestamp: Date?, eventID: String? = nil) {
        self.activity = activity
        self.timestamp = timestamp
        self.eventID = eventID
    }
}

public enum CodexEventClassifier {
    public static func classify(jsonLine: String) -> CodexActivityRecord? {
        guard let data = jsonLine.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        if let status = object["status"] as? String,
           let activity = CodexActivity(rawValue: status) {
            return CodexActivityRecord(
                activity: activity,
                timestamp: parseDate(object["timestamp"]),
                eventID: object["event_id"] as? String ?? object["turn_id"] as? String
            )
        }

        guard object["type"] as? String == "event_msg",
              let payload = object["payload"] as? [String: Any],
              let payloadType = payload["type"] as? String
        else {
            return nil
        }

        let activity: CodexActivity?
        switch payloadType {
        case "task_started":
            activity = .running
        case "task_complete":
            activity = .completed
        case "turn_aborted", "task_failed", "stream_error", "error":
            activity = .failed
        default:
            activity = nil
        }

        guard let activity else { return nil }
        let timestamp = parseDate(object["timestamp"])
            ?? parseDate(payload["completed_at"])
            ?? parseDate(payload["started_at"])

        return CodexActivityRecord(
            activity: activity,
            timestamp: timestamp,
            eventID: payload["turn_id"] as? String
        )
    }

    private static func parseDate(_ raw: Any?) -> Date? {
        guard let string = raw as? String else { return nil }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) {
            return date
        }

        return ISO8601DateFormatter().date(from: string)
    }
}

public enum CodexHookInstallError: LocalizedError {
    case invalidRootObject

    public var errorDescription: String? {
        switch self {
        case .invalidRootObject:
            "现有 hooks.json 不是有效的 JSON 对象，未进行修改。"
        }
    }
}

public struct CodexHooksInstaller: Sendable {
    public static let commandMarker = "CainiaoPetBridge"

    public init() {}

    public func isInstalled(at hooksURL: URL) -> Bool {
        guard let data = try? Data(contentsOf: hooksURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return false
        }
        return containsBridge(in: root)
    }

    public func install(at hooksURL: URL, bridgeExecutable: URL) throws {
        var root = try loadRoot(at: hooksURL)
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        hooks["UserPromptSubmit"] = installingGroup(
            in: cleanedGroups(hooks["UserPromptSubmit"]),
            command: shellQuote(bridgeExecutable.path) + " running"
        )
        hooks["Stop"] = installingGroup(
            in: cleanedGroups(hooks["Stop"]),
            command: shellQuote(bridgeExecutable.path) + " completed"
        )

        root["hooks"] = hooks
        if root["description"] == nil {
            root["description"] = "Local Codex lifecycle hooks. Cainiao Pet entries are added only after user confirmation."
        }

        try write(root, to: hooksURL)
    }

    public func uninstall(at hooksURL: URL) throws {
        guard FileManager.default.fileExists(atPath: hooksURL.path) else { return }
        var root = try loadRoot(at: hooksURL)
        guard var hooks = root["hooks"] as? [String: Any] else { return }

        for event in ["UserPromptSubmit", "Stop"] {
            let groups = cleanedGroups(hooks[event])
            if groups.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = groups
            }
        }

        root["hooks"] = hooks
        try write(root, to: hooksURL)
    }

    private func loadRoot(at url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexHookInstallError.invalidRootObject
        }
        return root
    }

    private func cleanedGroups(_ raw: Any?) -> [[String: Any]] {
        guard let groups = raw as? [[String: Any]] else { return [] }
        return groups.compactMap { group in
            guard let handlers = group["hooks"] as? [[String: Any]] else { return group }
            let retained = handlers.filter { handler in
                guard let command = handler["command"] as? String else { return true }
                return !command.contains(Self.commandMarker)
            }
            guard !retained.isEmpty else { return nil }
            var updated = group
            updated["hooks"] = retained
            return updated
        }
    }

    private func installingGroup(
        in groups: [[String: Any]],
        command: String
    ) -> [[String: Any]] {
        var result = groups
        result.append([
            "hooks": [[
                "type": "command",
                "command": command,
                "timeout": 3
            ]]
        ])
        return result
    }

    private func write(_ root: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: url, options: .atomic)
    }

    private func containsBridge(in value: Any) -> Bool {
        if let string = value as? String {
            return string.contains(Self.commandMarker)
        }
        if let array = value as? [Any] {
            return array.contains(where: containsBridge)
        }
        if let dictionary = value as? [String: Any] {
            return dictionary.values.contains(where: containsBridge)
        }
        return false
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
