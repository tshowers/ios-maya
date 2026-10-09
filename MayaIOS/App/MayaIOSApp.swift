import SwiftUI
import FirebaseCore
import UserNotifications
import TODDAuthKit
import TODDAwardsKit

@main
struct MayaIOSApp: App {
    @UIApplicationDelegateAdaptor(MayaAppDelegate.self) private var appDelegate
    @StateObject private var authService = AuthService()
    @StateObject private var entitlementService: EntitlementService
    @StateObject private var awardsService: AwardsService
    @StateObject private var socialStore: SocialStore
    private let chatViewModel: ChatViewModel

    init() {
        FirebaseApp.configure()

        let config = AppConfig.fromBundle()
        let authService = AuthService()
        _authService = StateObject(wrappedValue: authService)
        _awardsService = StateObject(wrappedValue: MayaAwards.makeService(authService: authService))
        let entitlementService = EntitlementService(
            apiClient: MayaAppStoreClient(config: config, authService: authService),
            authService: authService,
            config: config
        )
        _entitlementService = StateObject(wrappedValue: entitlementService)
        let socialAPI = SocialAPIClient(config: config, authService: authService)
        let socialStore = SocialStore(api: socialAPI)
        _socialStore = StateObject(wrappedValue: socialStore)
        // Maya's notes (push): Approve / Hold right on the notification.
        MayaPushService.shared.configure(api: socialAPI)
        MayaNotificationDelegate.shared.onChange = { Task { await socialStore.loadPosts(force: true) } }
        UNUserNotificationCenter.current().delegate = MayaNotificationDelegate.shared
        self.chatViewModel = ChatViewModel(
            apiClient: MarketingDirectorAPIClient(config: config),
            authService: authService,
            entitlementService: entitlementService,
            workspaceContextService: WorkspaceContextService(),
            conversationStore: ConversationStore()
        )
    }

    var body: some Scene {
        WindowGroup {
            if PaywallScreenshot.current != nil {
                NavigationStack { PaywallView(entitlementService: entitlementService) }
            } else {
                RootView(authService: authService, entitlementService: entitlementService, awardsService: awardsService, socialStore: socialStore, chatViewModel: chatViewModel)
                    .onOpenURL { url in
                        _ = GoogleSignInHelper.handle(url)
                    }
            }
        }
    }
}
