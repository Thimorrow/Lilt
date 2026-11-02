import Foundation
import UserNotifications

struct FocusNotificationPlan: Equatable {
    let deadline: Date
    let title: String

    init?(session: FocusSession) {
        guard session.phase == .running, let deadline = session.deadline, !session.needsFinish else { return nil }
        self.deadline = deadline
        title = session.intervals?.phase == .rest ? "Break complete" : "Focus complete"
    }
}

final class FocusNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let identifier = "lilt.focus.completion"
    private let center: UNUserNotificationCenter
    private var plan: FocusNotificationPlan?
    private var enabled: Bool?
    private var revision = 0
    private(set) var status = "off"
    private(set) var requestingPermission = false
    var onChange: (() -> Void)?
    var onOpen: (() -> Void)?

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        center.delegate = self
    }

    func refreshAuthorization(completion: (() -> Void)? = nil) {
        center.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                guard let self else { return }
                self.status = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional ? "allowed" : settings.authorizationStatus == .notDetermined ? "permission" : "denied"
                self.onChange?()
                completion?()
            }
        }
    }

    func requestPermission(completion: @escaping (Bool) -> Void) {
        guard !requestingPermission else { return }
        requestingPermission = true
        onChange?()
        center.requestAuthorization(options: [.alert]) { [weak self] allowed, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.requestingPermission = false
                self.refreshAuthorization { completion(allowed) }
            }
        }
    }

    func update(session: FocusSession, enabled: Bool) {
        let next = enabled && status == "allowed" ? FocusNotificationPlan(session: session) : nil
        guard next != plan || self.enabled != enabled else { return }
        revision += 1
        let token = revision
        self.enabled = enabled
        plan = next
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        if !enabled || session.phase != .completed { center.removeDeliveredNotifications(withIdentifiers: [Self.identifier]) }
        guard let next, next.deadline > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = next.title
        content.body = "Open Lilt to continue or finish."
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, next.deadline.timeIntervalSinceNow), repeats: false)
        center.add(UNNotificationRequest(identifier: Self.identifier, content: content, trigger: trigger)) { [weak self] error in
            guard error != nil else { return }
            DispatchQueue.main.async {
                guard let self, self.revision == token else { return }
                self.plan = nil
                self.status = "error"
                self.onChange?()
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            if response.actionIdentifier == UNNotificationDefaultActionIdentifier { self?.onOpen?() }
            completionHandler()
        }
    }
}

extension AppDelegate {
    func configureFocusNotifications() {
        focusNotifications?.update(session: focus.session, enabled: settings.value.focusNotificationsEnabled)
    }

    func enableFocusNotifications() {
        if isolatedRun { updateSettings(["focusNotificationsEnabled": true]); return }
        focusNotifications?.requestPermission { [weak self] allowed in
            guard let self else { return }
            if allowed { self.updateSettings(["focusNotificationsEnabled": true]) }
            else { self.sendSettings() }
        }
    }
}
