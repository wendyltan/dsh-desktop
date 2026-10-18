import SwiftUI

struct BridgeSession: Identifiable {
    let sessionId: String
    let title: String
    let cwd: String
    let live: Bool
    var id: String { sessionId }
}

struct BridgeModel: Identifiable {
    let provider: String
    let model: String
    let name: String
    var id: String { "\(provider):\(model)" }
}

enum NativeMetric {
    case quickPromptOpened, quickPromptSent, quickPromptFailed
}

extension Color {
    static let deepseekBlue = Color.blue
}

@main
struct QuickPromptPanelTests {
    static func main() {
        var failures = 0
        func expect(_ condition: Bool, _ label: String) {
            if condition { print("PASS  \(label)") }
            else { failures += 1; print("FAIL  \(label)") }
        }

        let panel = QuickPromptPanelController()
        let first = BridgeSession(sessionId: "one", title: "One", cwd: "/one", live: true)
        let second = BridgeSession(sessionId: "two", title: "Two", cwd: "/two", live: true)
        var openedSessionId: String?
        let completionModel = QuickPromptModel()
        let submittedText = "提问 A"
        completionModel.text = submittedText
        completionModel.text = "提问 B"
        completionModel.completeSend(to: second.sessionId, submittedText: submittedText)
        expect(completionModel.sentSessionId == second.sessionId, "successful send keeps the destination session visible")
        expect(completionModel.status.contains(second.sessionId), "success status names its destination session")
        expect(completionModel.text == "提问 B", "completion of A preserves a newer draft B")
        completionModel.text = submittedText
        completionModel.completeSend(to: second.sessionId, submittedText: submittedText)
        expect(completionModel.text.isEmpty, "completion clears the submitted draft when it is unchanged")
        completionModel.startNewPrompt()
        expect(completionModel.sentSessionId == nil, "new prompt clears the prior success result")

        panel.onOpenSession = { openedSessionId = $0 }
        let panelModel = Mirror(reflecting: panel).children.first(where: { $0.label == "model" })?.value as? QuickPromptModel
        panelModel?.completeSend(to: second.sessionId, submittedText: "")
        panel.openSentSession(second.sessionId)
        expect(openedSessionId == second.sessionId, "open-session action forwards the successful destination")
        expect(panelModel?.sentSessionId == nil, "opening a session dismisses the transient success state")

        let closePanel = QuickPromptPanelController()
        let closeModel = Mirror(reflecting: closePanel).children.first(where: { $0.label == "model" })?.value as? QuickPromptModel
        closeModel?.completeSend(to: second.sessionId, submittedText: "")
        closePanel.close()
        expect(closeModel?.sentSessionId == nil, "closing the panel dismisses the transient success state")

        panel.sessions = [first, second]
        panel.selectedSessionId = second.sessionId
        panel.sessions = [first, second]
        expect(panel.selectedSessionId == second.sessionId, "refresh retains a valid selection")

        panel.sessions = [first]
        expect(panel.selectedSessionId == nil, "refresh clears a removed selection")

        panel.sessions = [first]
        panel.selectedSessionId = first.sessionId
        panel.sessionsLoading = true
        expect(panel.sessionsLoading, "loading state is exposed")
        let model = Mirror(reflecting: panel).children.first(where: { $0.label == "model" })?.value as? QuickPromptModel
        expect(model != nil, "draft model is available for verification")
        model?.text = "keep this draft"
        var changedSelection: String? = "unset"
        panel.onSessionChange = { changedSelection = $0 }
        panel.sessionsError = "Could not load sessions"
        expect(panel.sessions.isEmpty && panel.selectedSessionId == nil, "failed fetch clears stale sessions and target")
        expect(changedSelection == nil, "failed fetch notifies that the target was cleared")
        expect(!panel.sessionsLoading, "failure ends loading")
        if let model { expect(model.text == "keep this draft", "failed fetch preserves draft text") }

        let duplicateTitleSessions = [
            BridgeSession(sessionId: "session-123456", title: "同名会话", cwd: "/work/project", live: true),
            BridgeSession(sessionId: "session-abcdef", title: "同名会话", cwd: "/work/project", live: true),
        ]
        let labelView = QuickPromptView(model: model!, send: {}, openClient: {}, openSession: { _ in }, close: {}, sessionChanged: { _ in }, onRetrySessions: nil)
        let labels = duplicateTitleSessions.map { labelView.sessionLabel(for: $0, among: duplicateTitleSessions) }
        expect(labels[0] != labels[1] && labels.allSatisfy { $0.contains("project") }, "same-title same-directory sessions get distinct readable labels")
        model?.sessions = duplicateTitleSessions
        expect(labelView.sentSessionLabel(for: duplicateTitleSessions[1].sessionId) == labels[1], "success handoff uses duplicate-title disambiguation")

        panel.modelsLoading = true
        expect(panel.modelsLoading && panel.modelsError == nil, "model list exposes loading state")
        var modelRetries = 0
        panel.onRetryModels = { modelRetries += 1 }
        panel.onRetryModels?()
        expect(modelRetries == 1, "model list retry hook runs")
        let request = panel.beginModelLoad()
        expect(panel.finishModelLoad(request, result: .success([BridgeModel(provider: "p", model: "m", name: "Model")])), "current model response is accepted")
        expect(panel.models.count == 1 && panel.modelsError == nil && !panel.modelsLoading, "model success clears loading and error")
        let stale = panel.beginModelLoad()
        let current = panel.beginModelLoad()
        expect(panel.finishModelLoad(current, result: .failure(NSError(domain: "test", code: 1))), "latest model response is accepted")
        expect(!panel.finishModelLoad(stale, result: .success([])), "stale model response is rejected")
        expect(panel.modelsError != nil && panel.models.isEmpty, "stale model response cannot replace current failure")

        var retries = 0
        panel.onRetrySessions = { retries += 1 }
        panel.onRetrySessions?()
        expect(retries == 1, "retry hook runs")

        if failures > 0 { exit(1) }
        print("all assertions passed")
    }
}
