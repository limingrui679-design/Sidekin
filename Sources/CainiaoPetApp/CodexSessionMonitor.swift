import CainiaoPetCore
import Foundation

@MainActor
final class CodexSessionMonitor {
    typealias ActivityHandler = (CodexActivity, Date, String?) -> Void

    var onActivity: ActivityHandler?

    private let sessionsRoot: URL
    private let eventInbox: URL
    private var offsets: [String: UInt64] = [:]
    private var remainders: [String: String] = [:]
    private var pollingTask: Task<Void, Never>?
    private var isPrimed = false

    init(
        sessionsRoot: URL = CainiaoPetPaths.defaultCodexSessionsURL(),
        eventInbox: URL = CainiaoPetPaths.eventInboxURL()
    ) {
        self.sessionsRoot = sessionsRoot
        self.eventInbox = eventInbox
    }

    func start() {
        guard pollingTask == nil else { return }
        prime()
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 850_000_000)
                self?.poll()
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func prime() {
        guard !isPrimed else { return }
        isPrimed = true

        let files = recentSessionFiles()
        for file in files {
            offsets[file.path] = fileSize(of: file)
        }
        offsets[eventInbox.path] = fileSize(of: eventInbox)

        guard let latest = files.first,
              let record = latestRelevantRecord(in: latest)
        else {
            return
        }

        let occurredAt = record.timestamp ?? modificationDate(of: latest) ?? Date()
        let age = Date().timeIntervalSince(occurredAt)

        switch record.activity {
        case .running where age < 60 * 60:
            onActivity?(.running, occurredAt, record.eventID)
        case .completed where age < 15:
            onActivity?(record.activity, occurredAt, record.eventID)
        case .failed where age < 15:
            onActivity?(record.activity, occurredAt, record.eventID)
        default:
            break
        }
    }

    private func poll() {
        let sessionFiles = recentSessionFiles().reversed()
        for file in sessionFiles {
            readNewLines(from: file)
        }
        readNewLines(from: eventInbox)
    }

    private func readNewLines(from url: URL) {
        let path = url.path
        let size = fileSize(of: url)
        let previousOffset = offsets[path] ?? 0
        let safeOffset = previousOffset <= size ? previousOffset : 0

        guard size > safeOffset,
              let handle = try? FileHandle(forReadingFrom: url)
        else {
            offsets[path] = size
            return
        }

        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: safeOffset)
            guard let data = try handle.readToEnd(), !data.isEmpty else {
                offsets[path] = size
                return
            }

            offsets[path] = safeOffset + UInt64(data.count)
            let chunk = (remainders[path] ?? "") + String(decoding: data, as: UTF8.self)
            var lines = chunk.components(separatedBy: "\n")
            remainders[path] = lines.removeLast()

            for line in lines where !line.isEmpty {
                guard let record = CodexEventClassifier.classify(jsonLine: line) else { continue }
                onActivity?(record.activity, record.timestamp ?? Date(), record.eventID)
            }
        } catch {
            offsets[path] = size
        }
    }

    private func latestRelevantRecord(in url: URL) -> CodexActivityRecord? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let size = fileSize(of: url)
        let tailLength: UInt64 = min(size, 512 * 1_024)

        do {
            try handle.seek(toOffset: size - tailLength)
            guard let data = try handle.readToEnd() else { return nil }
            let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
            return lines.reversed().lazy.compactMap {
                CodexEventClassifier.classify(jsonLine: String($0))
            }.first
        } catch {
            return nil
        }
    }

    private func recentSessionFiles() -> [URL] {
        guard FileManager.default.fileExists(atPath: sessionsRoot.path),
              let enumerator = FileManager.default.enumerator(
                at: sessionsRoot,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
              )
        else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            files.append(url)
        }

        return Array(
            files.sorted {
                (modificationDate(of: $0) ?? .distantPast) >
                (modificationDate(of: $1) ?? .distantPast)
            }.prefix(10)
        )
    }

    private func fileSize(of url: URL) -> UInt64 {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize
        else {
            return 0
        }
        return UInt64(max(0, size))
    }

    private func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
