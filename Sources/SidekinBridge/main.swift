import SidekinCore
import Foundation

@main
struct SidekinBridge {
    static func main() {
        defer {
            // Stop hooks require valid JSON on stdout. An empty object means "continue normally".
            print("{}")
        }

        guard CommandLine.arguments.count >= 2,
              let activity = CodexActivity(rawValue: CommandLine.arguments[1])
        else {
            return
        }

        let fileManager = FileManager.default
        let inboxURL = SidekinPaths.eventInboxURL(fileManager: fileManager)

        do {
            let standardInput = FileHandle.standardInput.readDataToEndOfFile()
            let hookInput = try? JSONSerialization.jsonObject(with: standardInput) as? [String: Any]

            try fileManager.createDirectory(
                at: inboxURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            var payload: [String: String] = [
                "status": activity.rawValue,
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ]
            if let turnID = hookInput?["turn_id"] as? String {
                payload["event_id"] = turnID
            }
            var data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            data.append(0x0A)

            if !fileManager.fileExists(atPath: inboxURL.path) {
                fileManager.createFile(atPath: inboxURL.path, contents: nil)
            }

            let handle = try FileHandle(forWritingTo: inboxURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // The bridge is deliberately advisory. It never blocks a Codex turn.
        }
    }
}
