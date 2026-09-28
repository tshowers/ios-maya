import SwiftUI
import TODDAwardsKit

/// Unlike `pulse-ios`'s `RootView` (which gates the entire app behind
/// sign-in), Maya's chat works signed-out, so this always shows `ChatView`.
struct RootView: View {
    @ObservedObject var authService: AuthService
    @ObservedObject var entitlementService: EntitlementService
    @ObservedObject var awardsService: AwardsService
    let chatViewModel: ChatViewModel

    var body: some View {
        ChatView(viewModel: chatViewModel, authService: authService, entitlementService: entitlementService, awardsService: awardsService)
            .onChange(of: authService.userId) { oldValue, newValue in
                // Pull this account's awards first (and push any earned
                // signed out), then record sign-up - so an award already
                // earned on another device isn't celebrated again.
                if oldValue == nil, newValue != nil {
                    Task {
                        await awardsService.sync()
                        awardsService.recordSignedUp()
                    }
                }
            }
            .task {
                if authService.userId != nil { await awardsService.sync() }
            }
            .fullScreenCover(item: Binding(
                get: { awardsService.pendingUnlock },
                set: { newValue in if newValue == nil { awardsService.dismissCurrentUnlock() } }
            )) { award in
                AwardUnlockView(
                    award: award,
                    appName: "Maya",
                    unlockedCount: awardsService.unlockedCount,
                    totalCount: awardsService.totalCount,
                    onContinue: { awardsService.dismissCurrentUnlock() }
                )
            }
    }
}
