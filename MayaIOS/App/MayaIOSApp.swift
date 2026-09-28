import SwiftUI
import FirebaseCore
import TODDAuthKit

@main
struct MayaIOSApp: App {
    @StateObject private var authService = AuthService()
    @StateObject private var entitlementService: EntitlementService
    private let chatViewModel: ChatViewModel

    init() {
        FirebaseApp.configure()

        let config = AppConfig.fromBundle()
        let authService = AuthService()
        _authService = StateObject(wrappedValue: authService)
        let entitlementService = EntitlementService(
            apiClient: MayaAppStoreClient(config: config, authService: authService),
            authService: authService,
            config: config
        )
        _entitlementService = StateObject(wrappedValue: entitlementService)
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
            RootView(authService: authService, entitlementService: entitlementService, chatViewModel: chatViewModel)
                .onOpenURL { url in
                    _ = GoogleSignInHelper.handle(url)
                }
        }
    }
}
