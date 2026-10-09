import Foundation
import UIKit
import UserNotifications

/// Maya's notes as push notifications (design_handoff_maya_social_gaps 3i):
/// the 9:00 AM review note, failures and pinned posts about to expire, sent
/// by todd-backend (mayaSocial/notes.js). Approve and Hold run from the
/// notification without opening the app; "Approve all" for several posts.
@MainActor
final class MayaPushService: ObservableObject {
    static let shared = MayaPushService()

    static let reviewCategory = "MAYA_SOCIAL_REVIEW"
    static let reviewManyCategory = "MAYA_SOCIAL_REVIEW_MANY"
    static let approveAction = "MAYA_SOCIAL_APPROVE"
    static let holdAction = "MAYA_SOCIAL_HOLD"
    static let approveAllAction = "MAYA_SOCIAL_APPROVE_ALL"
    static let openTodayAction = "MAYA_SOCIAL_OPEN_TODAY"

    /// Set when a notification is tapped; the app switches to Today.
    @Published var openToday = false

    private var api: SocialAPIClient?
    private var registeredToken: String?

    #if DEBUG
    private let environment = "sandbox"
    #else
    // TestFlight and App Store builds use Apple's production push service.
    private let environment = "production"
    #endif

    func configure(api: SocialAPIClient) {
        self.api = api
        let approve = UNNotificationAction(identifier: Self.approveAction, title: "Approve", options: [.authenticationRequired])
        let hold = UNNotificationAction(identifier: Self.holdAction, title: "Hold", options: [.authenticationRequired])
        let approveAll = UNNotificationAction(identifier: Self.approveAllAction, title: "Approve all", options: [.authenticationRequired])
        let openToday = UNNotificationAction(identifier: Self.openTodayAction, title: "Open Today", options: [.foreground])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: Self.reviewCategory, actions: [approve, hold], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.reviewManyCategory, actions: [approveAll, openToday], intentIdentifiers: []),
        ])
    }

    /// Asked once Maya Social is set up, not at launch.
    func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            if granted { UIApplication.shared.registerForRemoteNotifications() }
        } else {
            await registerIfAllowed()
        }
    }

    /// On launch and after sign-in, so the backend has this device's current token.
    func registerIfAllowed() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        if status == .authorized || status == .provisional {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func didRegister(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        registeredToken = token
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        Task { try? await api?.registerPushDevice(token: token, environment: environment, appVersion: version) }
    }

    /// Before signing out, so this phone stops getting the account's notes.
    func unregister() async {
        guard let token = registeredToken else { return }
        try? await api?.unregisterPushDevice(token: token)
        registeredToken = nil
    }

    /// Approve / Hold / Approve all from the notification.
    func handle(actionIdentifier: String, postIds: [String]) async {
        guard let api else { return }
        switch actionIdentifier {
        case Self.approveAction, Self.approveAllAction:
            for id in postIds { _ = try? await api.approve(id) }
        case Self.holdAction:
            for id in postIds { _ = try? await api.hold(id) }
        default:
            openToday = true
        }
    }
}

/// Hands notifications to MayaPushService and shows them while the app is open.
final class MayaNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = MayaNotificationDelegate()
    /// After an action, open screens refresh.
    var onChange: (() -> Void)?

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let postIds = (info["postIds"] as? [String]) ?? []
        let action = response.actionIdentifier == UNNotificationDefaultActionIdentifier ? MayaPushService.openTodayAction : response.actionIdentifier
        await MayaPushService.shared.handle(actionIdentifier: action, postIds: postIds)
        await MainActor.run { onChange?() }
    }
}

/// Apple hands the device token to the app delegate.
final class MayaAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in MayaPushService.shared.didRegister(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Simulator, or push not set up for this build: nothing to do.
    }
}
