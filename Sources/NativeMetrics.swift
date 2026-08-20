import Foundation

enum NativeMetric: String, CaseIterable {
    case notificationRequested
    case notificationScheduled
    case notificationFailed
    case approvalAttempted
    case approvalSucceeded
    case approvalFailed
    case approvalDeferredToWeb
    case quickPromptOpened
    case quickPromptSent
    case quickPromptFailed
    case guardianAutoRecovered
    case guardianManualRecovered
    case guardianSafeMode
}

struct NativeMetricsSnapshot: Codable {
    var schemaVersion = 1
    var startedAt: String
    var updatedAt: String
    var counts: [String: Int]
    var lastOutcome: [String: String]

    func count(_ metric: NativeMetric) -> Int { counts[metric.rawValue] ?? 0 }

    static func empty() -> NativeMetricsSnapshot {
        let now = NativeMetricsStore.timestamp()
        return NativeMetricsSnapshot(startedAt: now, updatedAt: now, counts: [:], lastOutcome: [:])
    }
}

/// Privacy-preserving, device-local counters for evaluating the native P0
/// control surface. It never stores prompt text, command text, callback URLs,
/// configuration contents, credentials, or session identifiers.
final class NativeMetricsStore {
    private let lock = NSLock()
    private var value: NativeMetricsSnapshot
    private let fileURL: URL
    var onChange: ((NativeMetricsSnapshot) -> Void)?

    init() {
        let dshHome = ProcessInfo.processInfo.environment["DSH_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".dsh", isDirectory: true)
        let directory = dshHome.appendingPathComponent("dsh-desktop", isDirectory: true)
        fileURL = directory.appendingPathComponent("native-metrics.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        value = Self.read(from: fileURL) ?? .empty()
    }

    var snapshot: NativeMetricsSnapshot {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func record(_ metric: NativeMetric, outcome: String? = nil) {
        lock.lock()
        value.counts[metric.rawValue, default: 0] += 1
        value.updatedAt = Self.timestamp()
        if let outcome { value.lastOutcome[metric.rawValue] = outcome }
        let changed = value
        persistLocked()
        lock.unlock()
        DispatchQueue.main.async { [weak self] in self?.onChange?(changed) }
    }

    static func loadSnapshot() -> NativeMetricsSnapshot {
        NativeMetricsStore().snapshot
    }

    static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static func read(from url: URL) -> NativeMetricsSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(NativeMetricsSnapshot.self, from: data)
    }

    private func persistLocked() {
        guard let data = try? JSONEncoder.pretty.encode(value) else { return }
        do {
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            // Metrics must never interfere with approvals, prompts, or recovery.
        }
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
