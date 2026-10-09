import Foundation
import UserNotifications

/// "I'll send you a note" (design 1a): a local notification when each post
/// opens for review, with Approve and Hold right on it. Rescheduled from
/// the posts every time the Social tabs load them; the server stays the
/// source of truth, so a stale reminder for an already-approved post just
/// approves it again.
enum SocialReviewReminders {
    static let category = "MAYA_SOCIAL_REVIEW"
    static let approveAction = "MAYA_SOCIAL_APPROVE"
    static let holdAction = "MAYA_SOCIAL_HOLD"
    private static let prefix = "maya-social-review-"

    /// Registers the actions. Call once at launch.
    static func registerCategory() {
        let approve = UNNotificationAction(identifier: approveAction, title: "Approve", options: [.authenticationRequired])
        let hold = UNNotificationAction(identifier: holdAction, title: "Hold", options: [.authenticationRequired])
        let category = UNNotificationCategory(identifier: category, actions: [approve, hold], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// Asks once, after Maya Social is set up.
    static func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Replaces the pending reminders with one per drafted post whose review
    /// window opens in the future.
    static func schedule(for posts: [SocialPost], timeZone: TimeZone) {
        let center = UNUserNotificationCenter.current()
        Task {
            let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: pending)
            let now = Date()
            for post in posts where post.status == .drafted {
                guard let opens = SocialDates.instant(post.reviewOpensAt), opens > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = "A post needs you"
                content.body = "\(post.title). It goes out \(SocialDates.slot(post, today: SocialDates.key(opens, timeZone: timeZone)).replacingOccurrences(of: "Today", with: "today")) unless you hold it."
                content.sound = .default
                content.categoryIdentifier = category
                content.userInfo = ["postId": post.id]
                let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: opens)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                try? await center.add(UNNotificationRequest(identifier: prefix + post.id, content: content, trigger: trigger))
            }
        }
    }
}

/// Handles Approve / Hold tapped on a reminder, and shows reminders while
/// the app is open.
final class SocialNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = SocialNotificationDelegate()
    var api: SocialAPIClient?
    /// Called after an action so open screens can refresh.
    var onChange: (() -> Void)?

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let postId = response.notification.request.content.userInfo["postId"] as? String, let api else { return }
        switch response.actionIdentifier {
        case SocialReviewReminders.approveAction:
            _ = try? await api.approve(postId)
        case SocialReviewReminders.holdAction:
            _ = try? await api.hold(postId)
        default:
            break
        }
        await MainActor.run { onChange?() }
    }
}
