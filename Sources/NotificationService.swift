import Foundation
import AppKit
import UserNotifications

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private enum Action {
        static let allow = "DSH_APPROVAL_ALLOW"
        static let reject = "DSH_APPROVAL_REJECT"
        static let open = "DSH_OPEN_TASK"
    }
    private enum Category {
        static let approval = "DSH_APPROVAL"
        static let information = "DSH_INFORMATION"
    }

    var onOpenClient: (() -> Void)?
    var onActionResult: ((String) -> Void)?
    var onMetric: ((NativeMetric, String?) -> Void)?
    var callbackToken: String?

    func start() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let allow = UNNotificationAction(identifier: Action.allow, title: "允许一次")
        let reject = UNNotificationAction(identifier: Action.reject, title: "拒绝", options: .destructive)
        let open = UNNotificationAction(identifier: Action.open, title: "打开任务", options: .foreground)
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Category.approval, actions: [allow, reject, open], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.information, actions: [open], intentIdentifiers: []),
        ])
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            if let error { DispatchQueue.main.async { self?.onActionResult?("通知权限请求失败：\(error.localizedDescription)") } }
            else if !granted { DispatchQueue.main.async { self?.onActionResult?("系统通知未获授权，可在系统设置中开启。") } }
        }
    }

    /// Approval interception must fail closed when macOS notifications are not
    /// authorized; otherwise Harness would wait on an invisible native prompt.
    func canDeliverApproval() -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var allowed = false
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            semaphore.signal()
        }
        return semaphore.wait(timeout: .now() + 1) == .success && allowed
    }

    func publish(_ event: DesktopBridgeEvent) {
        guard event.type != "bridge.connected", event.type != "task.started", event.type != "task.progress" else { return }
        onMetric?(.notificationRequested, event.type)
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.message
        content.sound = .default
        content.categoryIdentifier = event.type == "approval.requested" ? Category.approval : Category.information
        var info: [String: String] = ["eventId": event.id, "eventType": event.type]
        if let sessionId = event.sessionId { info["sessionId"] = sessionId }
        if let callback = event.callbackURL { info["callbackURL"] = callback }
        content.userInfo = info
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "dsh.\(event.id)", content: content, trigger: nil)
        ) { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    self?.onMetric?(.notificationFailed, "system-rejected")
                    self?.onActionResult?("通知发送失败：\(error.localizedDescription)")
                } else {
                    self?.onMetric?(.notificationScheduled, event.type)
                }
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        defer { completionHandler() }
        switch response.actionIdentifier {
        case Action.allow: answer(response, outcome: "allowed-once")
        case Action.reject: answer(response, outcome: "rejected")
        case Action.open, UNNotificationDefaultActionIdentifier:
            if response.notification.request.content.categoryIdentifier == Category.approval {
                answer(response, outcome: "defer-to-web", openAfter: true)
            } else {
                DispatchQueue.main.async { [weak self] in self?.onOpenClient?() }
            }
        default: break
        }
    }

    private func answer(_ response: UNNotificationResponse, outcome: String, openAfter: Bool = false) {
        onMetric?(.approvalAttempted, outcome)
        let info = response.notification.request.content.userInfo
        guard let text = info["callbackURL"] as? String,
              let url = EventBridge.validatedLoopbackURL(text),
              let eventId = info["eventId"] as? String else {
            DispatchQueue.main.async { [weak self] in
                self?.onMetric?(.approvalFailed, "invalid-callback")
                self?.onActionResult?("审批回调不可用，已打开客户端供你处理。")
                self?.onOpenClient?()
            }
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let callbackToken { request.setValue("Bearer \(callbackToken)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "protocolVersion": EventBridge.protocolVersion,
            "eventId": eventId,
            "outcome": outcome,
        ])
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            let succeeded = error == nil && (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } == true
            DispatchQueue.main.async {
                if succeeded {
                    self?.onMetric?(.approvalSucceeded, outcome)
                    if outcome == "defer-to-web" { self?.onMetric?(.approvalDeferredToWeb, "user-opened-task") }
                    let message = outcome == "allowed-once" ? "已允许一次。" : (outcome == "rejected" ? "已拒绝。" : "已转到客户端处理。")
                    self?.onActionResult?(message)
                    if openAfter { self?.onOpenClient?() }
                }
                else {
                    self?.onMetric?(.approvalFailed, error == nil ? "http-rejected" : "network-error")
                    self?.onActionResult?("审批未送达，仍保持待处理状态。")
                    self?.onOpenClient?()
                }
            }
        }.resume()
    }
}
