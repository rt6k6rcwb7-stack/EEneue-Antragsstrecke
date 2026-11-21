import Foundation
import UserNotifications
import FitnessCore

/// Lokale Benachrichtigung zum Pausenende, falls die App im Hintergrund ist (z. B. Bildschirm gesperrt).
enum RestNotifications {
    static let id = "rest-end"

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func schedule(for run: WorkoutRun, now: Date) {
        cancel()
        guard case .resting(let until, _) = run.phase, until > now else { return }
        let content = UNMutableNotificationContent()
        content.title = "Pause vorbei"
        content.body = "Weiter mit dem nächsten Satz."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, until.timeIntervalSince(now)), repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}
