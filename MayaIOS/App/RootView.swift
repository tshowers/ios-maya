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
    @ObservedObject private var push = MayaPushService.shared
    let chatViewModel: ChatViewModel

    private enum Tab: Hashable { case maya, today, calendar, strategy }

    /// Tab bar icons don't scale, so Maya's avatar is drawn at 24pt, round (3a).
    private static let tabAvatar: UIImage = {
        let size = CGSize(width: 24, height: 24)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).addClip()
            UIImage(named: "MayaAvatar")?.draw(in: CGRect(origin: .zero, size: size))
        }
        return image.withRenderingMode(.alwaysOriginal)
    }()
    #if DEBUG
    /// Screenshots: launch with -socialToday to open on Today.
    @State private var tab: Tab = ProcessInfo.processInfo.arguments.contains("-socialToday") ? .today : .maya
    #else
    @State private var tab: Tab = .maya
    #endif
    /// The Light/Dark pill in the Social header (gaps 2a); empty follows the system.
    @AppStorage(SocialAppearance.key) private var theme = ""

    var body: some View {
        TabView(selection: $tab) {
            ChatView(viewModel: chatViewModel, authService: authService, entitlementService: entitlementService, awardsService: awardsService)
                .tabItem { Label { Text("Maya") } icon: { Image(uiImage: Self.tabAvatar) } }
                .tag(Tab.maya)

            socialTab("Today", systemImage: "checklist") { path in SocialTodayView(store: socialStore, path: path) }.tag(Tab.today)
            socialTab("Calendar", systemImage: "calendar") { path in SocialCalendarView(store: socialStore, path: path) }.tag(Tab.calendar)
            socialTab("Strategy", systemImage: "target") { path in SocialStrategyView(store: socialStore, path: path) }.tag(Tab.strategy)
        }
        .tint(SocialTheme.text)
        .preferredColorScheme(SocialAppearance.scheme(theme))
        .onChange(of: push.openToday) { _, open in
            if open {
                tab = .today
                push.openToday = false
                Task { await socialStore.loadPosts(force: true) }
            }
        }
            .onChange(of: authService.userId) { oldValue, newValue in
                if oldValue != newValue { socialStore.reset() }
                if newValue != nil { Task { await MayaPushService.shared.registerIfAllowed() } }
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
