import Foundation
import LoopKit
import UserNotifications

extension Notification.Name {
    static let trioCriticalAlertDiagnosticScheduleResult =
        Notification.Name("Trio.criticalAlertDiagnostic.scheduleResult")
}

protocol TrioUserNotificationAlertResponder: AnyObject {
    func handleAcknowledgement(identifier: Alert.Identifier)
}

final class TrioUserNotificationAlertScheduler {
    weak var responder: TrioUserNotificationAlertResponder?

    private let notificationCenter: UNUserNotificationCenter

    init(notificationCenter: UNUserNotificationCenter) {
        self.notificationCenter = notificationCenter
    }

    /// `silenced` posts the notification without any sound. Used when another
    /// channel (AlarmKit) is already sounding this alert, so the two don't
    /// overlap into one very loud alarm.
    func schedule(_ alert: Alert, muted: Bool, soundURL: URL?, silenced: Bool = false) {
        let request = makeRequest(alert: alert, muted: muted, soundURL: soundURL, silenced: silenced)
        notificationCenter.add(request) { error in
            if let error = error {
                warning(.alerts, "Scheduling alert notification \(alert.identifier.value) failed", error: error)
            }
            // Report real notification scheduling errors only for temporary
            // diagnostic alerts; this does not prove OS audio was delivered.
            if BaseTrioAlertManager.isDiagnostic(alert.identifier) {
                let identifier = request.identifier
                let errorText = error?.localizedDescription
                DispatchQueue.main.async {
                    var details = ["identifier": identifier]
                    if let errorText { details["error"] = errorText }
                    NotificationCenter.default.post(
                        name: .trioCriticalAlertDiagnosticScheduleResult,
                        object: nil,
                        userInfo: details
                    )
                }
            }
        }
    }

    func unschedule(identifier: Alert.Identifier) {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier.value])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier.value])
    }

    private func makeRequest(alert: Alert, muted: Bool, soundURL: URL?, silenced: Bool) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = alert.backgroundContent.title
        content.body = alert.backgroundContent.body
        content.threadIdentifier = alert.identifier.managerIdentifier
        content.userInfo = [
            AlertUserInfoKey.managerIdentifier.rawValue: alert.identifier.managerIdentifier,
            AlertUserInfoKey.alertIdentifier.rawValue: alert.identifier.alertIdentifier
        ]
        content.interruptionLevel = alert.interruptionLevel.unNotificationLevel
        // A critical interruption level can use the default critical sound
        // when sound is nil. Request explicit zero-volume audio while AlarmKit
        // is the audible channel so the native UN does not sound as well.
        content.sound = silenced
            ? (alert.interruptionLevel == .critical ? .defaultCriticalSound(withAudioVolume: 0) : nil)
            : sound(for: alert, muted: muted, soundURL: soundURL)
        // Surface the four quick-snooze actions (15 min / 1 h / 3 h / 6 h)
        // on both phone and watch lock-screen notifications. The category +
        // its actions are registered by `NotificationCategoryFactory` on
        // both the phone (`BaseUserNotificationsManager`) and watch
        // (`WatchNotificationHandler`) UN delegates.
        content.categoryIdentifier = NotificationCategoryIdentifier.trioAlert.rawValue

        return UNNotificationRequest(
            identifier: alert.identifier.value,
            content: content,
            trigger: alert.trigger.unTrigger
        )
    }

    private func sound(for alert: Alert, muted: Bool, soundURL: URL?) -> UNNotificationSound? {
        let isCritical = alert.interruptionLevel == .critical
        if muted {
            return isCritical ? .defaultCriticalSound(withAudioVolume: 0) : nil
        }
        switch alert.sound {
        case .none,
             .vibrate:
            return isCritical ? .defaultCriticalSound(withAudioVolume: 0) : nil
        case let .sound(name):
            if let filename = soundURL?.lastPathComponent {
                let unName = UNNotificationSoundName(rawValue: filename)
                return isCritical ? .criticalSoundNamed(unName) : UNNotificationSound(named: unName)
            }
            let unName = UNNotificationSoundName(name)
            return isCritical ? .criticalSoundNamed(unName) : UNNotificationSound(named: unName)
        }
    }
}

private extension Alert.InterruptionLevel {
    var unNotificationLevel: UNNotificationInterruptionLevel {
        switch self {
        case .active: return .active
        case .timeSensitive: return .timeSensitive
        case .critical: return .critical
        }
    }
}

private extension Alert.Trigger {
    var unTrigger: UNNotificationTrigger? {
        switch self {
        case .immediate:
            return nil
        case let .delayed(interval):
            return UNTimeIntervalNotificationTrigger(timeInterval: max(interval, 1), repeats: false)
        case let .repeating(interval):
            return UNTimeIntervalNotificationTrigger(timeInterval: max(interval, 60), repeats: true)
        }
    }
}
