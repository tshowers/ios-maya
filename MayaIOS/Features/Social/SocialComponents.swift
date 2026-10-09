import SwiftUI
import TODDAuthKit

// MARK: - Small pieces (design 1l-1n, gaps 3a-3j)

struct SocialChip: View {
    let text: String
    let colors: (bg: Color, fg: Color)

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(colors.bg, in: Capsule())
            .foregroundStyle(colors.fg)
    }
}

struct SocialPillButtonStyle: ButtonStyle {
    enum Kind { case primary, plain, onCard, ink }
    var kind: Kind = .plain
    var height: CGFloat = 44

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: height >= 50 ? 17 : 15, weight: .bold))
            .frame(maxWidth: .infinity, minHeight: height)
            .padding(.horizontal, 16)
            .background(background, in: Capsule())
            .foregroundStyle(foreground)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }

    private var background: Color {
        switch kind {
        case .primary: return SocialTheme.blue
        case .plain: return SocialTheme.surface
        case .onCard: return SocialTheme.bg
        case .ink: return SocialTheme.text
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary: return .white
        case .ink: return SocialTheme.bg
        default: return SocialTheme.text
        }
    }
}

struct MayaAvatar: View {
    var size: CGFloat = 28

    var body: some View {
        Image("MayaAvatar")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size, alignment: .leading)
            .clipShape(Circle())
            .accessibilityHidden(true)
    }
}

struct SocialKicker: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .bold))
            .kerning(1)
            .foregroundStyle(SocialTheme.muted)
    }
}

/// A yellow / blue / pink notice along the top of a screen.
struct SocialNotice<Action: View>: View {
    let tint: String
    let text: String
    @ViewBuilder var action: () -> Action

    var body: some View {
        let colors = SocialTheme.tint(tint)
        VStack(alignment: .leading, spacing: 10) {
            Text(text).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
            action()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(colors.bg, in: RoundedRectangle(cornerRadius: 20))
        .foregroundStyle(colors.fg)
    }
}

/// Explains a rule in place (1q's "?" popovers).
struct SocialHelpButton: View {
    let title: String
    let text: String
    @State private var isShowing = false

    var body: some View {
        Button { isShowing = true } label: {
            Text("?")
                .font(.system(size: 13, weight: .bold))
                .frame(width: 24, height: 24)
                .background(SocialTheme.surface2, in: Circle())
                .foregroundStyle(SocialTheme.text)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("What does \(title.lowercased()) mean?")
        .popover(isPresented: $isShowing) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                Text(text).font(.subheadline)
            }
            .padding(20)
            .frame(maxWidth: 320)
            .presentationCompactAdaptation(.popover)
        }
    }

    static func autoApprove(hours: Int) -> SocialHelpButton {
        SocialHelpButton(title: "Auto-approve", text: "I draft each post ahead of time. If you don’t hold it within \(hours) hours, it’s approved and goes out in its slot. Change the hours in Social settings.")
    }

    static let hold = SocialHelpButton(title: "Hold", text: "A held post keeps its slot. If the slot arrives and it’s still held, nothing goes out that day, and every unpinned post behind it moves back a day.")
    static let pinned = SocialHelpButton(title: "Pinned", text: "Pinned posts are tied to a date, like an event. They never move. If one isn’t approved by its date, it expires.")
    static let offStrategy = SocialHelpButton(title: "Off-strategy", text: "I check every post against the strategy. If one doesn’t fit a pillar, or makes a claim that isn’t in your profile, I suggest a version that does.")
}

// MARK: - Theme (the Light/Dark pill, 2a)

enum SocialAppearance {
    static let key = "maya.theme"

    static func scheme(_ stored: String) -> ColorScheme? {
        stored == "dark" ? .dark : stored == "light" ? .light : nil
    }
}

// MARK: - Routes

enum SocialRoute: Hashable {
    case signIn
    case unlock
    case paywall
    case profile
    case newPost
}

// MARK: - Header (gaps 2a, phone)

/// Avatar + the tab's title, then "+" (when it applies), the theme circle
/// and the Menu pill. Help and Profile live in the Menu.
struct SocialHeader: View {
    let title: String
    var showNewPost = false
    var canPost = true
    var onNewPost: () -> Void = {}
    var onProfile: (() -> Void)?
    var onSignOut: (() -> Void)?

    @AppStorage(SocialAppearance.key) private var theme = ""
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 8) {
            MayaAvatar(size: 32)
            Text(title).font(.system(size: 18, weight: .bold)).foregroundStyle(SocialTheme.text)
            Spacer()
            if showNewPost {
                Button(action: onNewPost) {
                    Image(systemName: "plus").font(.system(size: 17, weight: .bold))
                        .frame(width: 40, height: 40)
                        .background(canPost ? SocialTheme.blue : SocialTheme.surface, in: Circle())
                        .foregroundStyle(canPost ? .white : SocialTheme.muted)
                }
                .disabled(!canPost)
                .accessibilityLabel("New post")
            }
            Button {
                theme = scheme == .dark ? "light" : "dark"
            } label: {
                Image(systemName: scheme == .dark ? "sun.max" : "moon").font(.system(size: 16, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(SocialTheme.surface, in: Circle())
                    .foregroundStyle(SocialTheme.text)
            }
            .accessibilityLabel(scheme == .dark ? "Switch to light mode" : "Switch to dark mode")
            Menu {
                if let onProfile { Button { onProfile() } label: { Label("Social settings", systemImage: "slider.horizontal.3") } }
                Button { openURL(URL(string: "https://social.taliferro.tech/help")!) } label: { Label("Help", systemImage: "questionmark.circle") }
                Button { openURL(URL(string: "https://social.taliferro.tech/about")!) } label: { Label("About Maya Social", systemImage: "info.circle") }
                if let onSignOut {
                    Section { Button(role: .destructive) { onSignOut() } label: { Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right") } }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal").font(.system(size: 15, weight: .bold))
                    Text("Menu").font(.system(size: 15, weight: .bold))
                }
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(SocialTheme.text, in: Capsule())
                .foregroundStyle(SocialTheme.bg)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
}

// MARK: - Gate

/// Each Social tab: sign in (3d), subscribe (3e), unlock, first run (3f),
/// setup (3g, 3h) before the tab's own content. Setup screens hide the tab bar.
struct SocialTab<Content: View>: View {
    let title: String
    var showsNewPost = true
    @ObservedObject var authService: AuthService
    @ObservedObject var entitlementService: EntitlementService
    @ObservedObject var sessionGate: SessionUnlockGate
    @ObservedObject var store: SocialStore
    @ViewBuilder var content: (_ path: Binding<[SocialRoute]>) -> Content

    @State private var path: [SocialRoute] = []

    private var isSetup: Bool {
        guard authService.currentUser != nil, sessionGate.isUnlocked, entitlementService.isEntitled else { return false }
        return store.access == .firstRun || store.access == .noStrategy
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                SocialHeader(
                    title: isSetup ? "Setup" : title,
                    showNewPost: showsNewPost && store.access == .ready && entitlementService.isEntitled,
                    canPost: store.canPost,
                    onNewPost: { path = [.newPost] },
                    onProfile: entitlementService.isEntitled && authService.currentUser != nil ? { path = [.profile] } : nil,
                    onSignOut: authService.currentUser != nil ? {
                        Task { await MayaPushService.shared.unregister() }
                        try? authService.signOut()
                    } : nil
                )
                gated.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(SocialTheme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .toolbar(isSetup ? .hidden : .visible, for: .tabBar)
            .navigationDestination(for: SocialRoute.self) { route in
                switch route {
                case .signIn:
                    MayaOnboardingView(authService: authService) { path = [] }
                case .unlock:
                    BiometricLockView(reason: "Unlock to restore your TODD session.") {
                        sessionGate.markUnlocked()
                        path = []
                    }
                case .paywall:
                    PaywallView(entitlementService: entitlementService)
                case .profile:
                    SocialProfileView(store: store)
                case .newPost:
                    NewSocialPostView(store: store) { path = [] }
                }
            }
        }
        .tint(SocialTheme.blue)
        .alert("That didn’t save", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(store.errorMessage ?? "Try again.")
        }
    }

    @ViewBuilder
    private var gated: some View {
        if authService.currentUser == nil {
            SocialSignedOutView { path = [.signIn] }
        } else if !sessionGate.isUnlocked {
            VStack(spacing: 16) {
                Text("Unlock to see your social calendar.").foregroundStyle(SocialTheme.muted)
                Button("Unlock") { path = [.unlock] }.buttonStyle(SocialPillButtonStyle(kind: .primary)).frame(maxWidth: 240)
            }
        } else if entitlementService.isLoadingEntitlement {
            ProgressView()
        } else if !entitlementService.isEntitled {
            SocialNoPlanView(email: authService.userEmail ?? "", entitlementService: entitlementService) { path = [.paywall] }
        } else {
            switch store.access {
            case .loading:
                ProgressView().task { await store.load() }
            case .failed(let message):
                SocialLoadErrorView(message: message) { Task { await store.load() } }
            case .firstRun:
                SocialWelcomeView(store: store)
            case .noStrategy:
                SocialSetupView(store: store) { path = [.profile] }
            case .ready:
                content($path)
            }
        }
    }
}

// MARK: - 3d, 3e, 2r

/// 3d: signed out, inside the Social tabs.
struct SocialSignedOutView: View {
    let onSignIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            MayaAvatar(size: 64)
            SocialChip(text: "INCLUDED WITH MAYA", colors: SocialTheme.tint("green"))
            Text("Sign in and I’ll run your social media.").font(.system(size: 30, weight: .bold)).kerning(-0.8)
            Text("I plan a post a day from your company profile. You approve or hold.").font(.system(size: 17)).foregroundStyle(SocialTheme.muted)
            Spacer()
            Button("Sign in", action: onSignIn).buttonStyle(SocialPillButtonStyle(kind: .primary, height: 54))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }
}

/// 3e: signed in without a Maya plan.
struct SocialNoPlanView: View {
    let email: String
    @ObservedObject var entitlementService: EntitlementService
    let onSeePlans: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            MayaAvatar(size: 64)
            Text("Social comes with a Maya plan.").font(.system(size: 30, weight: .bold)).kerning(-0.8)
            Text("You’re signed in as \(email), but this account doesn’t have Maya yet. Every plan includes Social at no extra cost.")
                .font(.system(size: 17)).foregroundStyle(SocialTheme.muted)
            Spacer()
            Button("See Maya plans", action: onSeePlans).buttonStyle(SocialPillButtonStyle(kind: .primary, height: 54))
            Button("Restore purchase") { Task { await entitlementService.restorePurchases() } }
                .font(.system(size: 15, weight: .bold)).foregroundStyle(SocialTheme.blueInk).frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }
}

/// 2r on a phone.
struct SocialLoadErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "exclamationmark.circle").font(.system(size: 28, weight: .semibold))
                .frame(width: 64, height: 64).background(SocialTheme.tint("pink").bg, in: Circle()).foregroundStyle(SocialTheme.tint("pink").fg)
            Text("I couldn’t load your calendar.").font(.system(size: 28, weight: .bold))
            Text("Your posts are safe and still going out on schedule. This is a problem loading the page, not with your plan.")
                .font(.system(size: 16)).foregroundStyle(SocialTheme.muted)
            Button { onRetry() } label: { Label("Try again", systemImage: "arrow.clockwise") }
                .buttonStyle(SocialPillButtonStyle(kind: .primary, height: 50)).frame(maxWidth: 220)
            Text(message).font(.system(size: 13)).foregroundStyle(SocialTheme.muted)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }
}

/// A post's image (2l), shown on phone cards and the post sheet.
struct SocialPostImage: View {
    let image: PostImage?
    var height: CGFloat = 150

    var body: some View {
        if let image {
            ZStack {
                RoundedRectangle(cornerRadius: 22).fill(SocialTheme.surface2)
                if image.status == "ready", let url = image.url.flatMap(URL.init(string:)) {
                    AsyncImage(url: url) { phase in
                        if let picture = phase.image { picture.resizable().scaledToFill() } else { ProgressView() }
                    }
                } else if image.status == "pending" || image.status == "making" {
                    VStack(spacing: 8) { ProgressView(); Text("Making the image from my brief…").font(.system(size: 13, weight: .bold)) }
                        .foregroundStyle(SocialTheme.muted)
                } else {
                    VStack(spacing: 6) { Image(systemName: "photo"); Text("No image").font(.system(size: 13, weight: .bold)) }
                        .foregroundStyle(SocialTheme.muted)
                }
            }
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .accessibilityLabel(image.brief ?? "Post image")
        }
    }
}
