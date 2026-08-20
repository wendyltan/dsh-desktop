import Foundation

@main
struct VerifyNativeMetrics {
    static func main() {
        let store = NativeMetricsStore()
        store.record(.notificationRequested, outcome: "task.completed")
        store.record(.notificationScheduled, outcome: "task.completed")
        store.record(.quickPromptOpened)
        store.record(.quickPromptSent)

        let snapshot = NativeMetricsStore.loadSnapshot()
        precondition(snapshot.count(.notificationRequested) == 1)
        precondition(snapshot.count(.notificationScheduled) == 1)
        precondition(snapshot.count(.quickPromptOpened) == 1)
        precondition(snapshot.count(.quickPromptSent) == 1)
        precondition(snapshot.lastOutcome[NativeMetric.notificationRequested.rawValue] == "task.completed")

        let home = ProcessInfo.processInfo.environment["DSH_HOME"]!
        let path = URL(fileURLWithPath: home).appendingPathComponent("dsh-desktop/native-metrics.json").path
        let permissions = (try? FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber)?.intValue
        precondition(permissions == 0o600)
        let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        for forbidden in ["prompt", "command", "callbackURL", "sessionId", "credential"] {
            precondition(!text.contains(forbidden))
        }
        print("Native metrics verification passed: local counters, 0600 permissions, no sensitive payload fields")
    }
}
