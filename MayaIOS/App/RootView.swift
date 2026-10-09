import SwiftUI
import TODDAwardsKit

/// Maya, plus Maya Social (design_handoff_maya_social): Maya Social comes
/// with the Maya subscription, so it lives in this app as three tabs next
/// to the chat. Maya's chat works signed-out (unlike `pulse-ios`); the
/// Social tabs show their own sign-in / subscribe doorway (SocialTab).
struct RootView: View {
    @ObservedObject var authService: AuthService
    @ObservedObject var entitlementService: EntitlementService
    @ObservedObject var awardsService: AwardsService
    @ObservedObject var socialStore: SocialStore
    let chatViewModel: ChatViewModel

    var body: some View {
        TabView {
            ChatView(viewModel: chatViewModel, authService: authService, entitlementService: entitlementService, awardsService: awardsService)
                .tabItem { Label("Maya", systemImage: "bubble.left.and.text.bubble.right") }

            socialTab("Today", systemImage: "sun.max") { path in SocialTodayView(store: socialStore, path: path) }
            socialTab("Calendar", systemImage: "calendar") { path in SocialCalendarView(store: socialStore, path: path) }
            socialTab("Strategy", systemImage: "target") { path in SocialStrategyView(store: socialStore, path: path) }
        }
        .tint(MayaTheme.accent)
            .onChange(of: authService.userId) { oldValue, newValue in
                if oldValue != newValue { socialStore.reset() }
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

    private func socialTab<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: @escaping (Binding<[SocialRoute]>) -> Content) -> some View {
        SocialTab(title: title, authService: authService, entitlementService: entitlementService, sessionGate: authService.sessionGate, store: socialStore, content: content)
            .tabItem { Label(title, systemImage: systemImage) }
    }
}
