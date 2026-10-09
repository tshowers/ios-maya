import SwiftUI
import TODDAuthKit

// MARK: - Small pieces (design 1l-1n)

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

/// Explains a rule in place (design 1q's "?" popovers, as a small sheet).
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
        SocialHelpButton(title: "Auto-approve", text: "I draft each post ahead of time. If you don’t hold it within \(hours) hours, it’s approved and goes out in its slot. Change the hours in Social profile.")
    }

    static let hold = SocialHelpButton(title: "Hold", text: "A held post keeps its slot. If the slot arrives and it’s still held, nothing goes out that day, and every unpinned post behind it moves back a day.")
    static let pinned = SocialHelpButton(title: "Pinned", text: "Pinned posts are tied to a date, like an event. They never move. If one isn’t approved by its date, it expires.")
}

// MARK: - Routes

enum SocialRoute: Hashable {
    case signIn
    case unlock
    case paywall
    case profile
    case newPost
}

// MARK: - Gate

/// Wraps each Social tab: sign in, unlock, subscribe, first run (1p) and
/// setup (1h/1i/1n) come before the tab's own content.
struct SocialTab<Content: View>: View {
    let title: String
    @ObservedObject var authService: AuthService
    @ObservedObject var entitlementService: EntitlementService
    @ObservedObject var sessionGate: SessionUnlockGate
    @ObservedObject var store: SocialStore
    @ViewBuilder var content: (_ path: Binding<[SocialRoute]>) -> Content

    @State private var path: [SocialRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                SocialTheme.bg.ignoresSafeArea()
                gated
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
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
        .alert("Something went wrong", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var gated: some View {
        if authService.currentUser == nil {
            SocialDoorwayView(signedIn: false) { path = [.signIn] }
        } else if !sessionGate.isUnlocked {
            VStack(spacing: 16) {
                Text("Unlock to see your social calendar.").foregroundStyle(SocialTheme.muted)
                Button("Unlock") { path = [.unlock] }.buttonStyle(SocialPillButtonStyle(kind: .primary)).frame(maxWidth: 240)
            }
        } else if entitlementService.isLoadingEntitlement {
            ProgressView()
        } else if !entitlementService.isEntitled {
            SocialDoorwayView(signedIn: true) { path = [.paywall] }
        } else {
            switch store.access {
            case .loading:
                ProgressView().task { await store.load() }
            case .failed(let message):
                VStack(spacing: 14) {
                    Text(message).foregroundStyle(SocialTheme.muted).multilineTextAlignment(.center)
                    Button("Try again") { Task { await store.load() } }.buttonStyle(SocialPillButtonStyle()).frame(maxWidth: 200)
                }
                .padding()
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

// MARK: - Doorway (1o)

struct SocialDoorwayView: View {
    let signedIn: Bool
    let onAction: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SocialChip(text: "INCLUDED WITH MAYA", colors: SocialTheme.tint("green"))
                Text("Maya runs your social media.")
                    .font(.system(size: 38, weight: .bold))
                    .kerning(-1.2)
                    .foregroundStyle(SocialTheme.text)
                Text("She builds a posting strategy from your company profile and keeps something going out every day. You approve or hold posts. The plan and the calendar are hers.")
                    .font(.system(size: 17))
                    .foregroundStyle(SocialTheme.muted)
                Button(signedIn ? "Subscribe to Maya" : "I have Maya. Sign in", action: onAction)
                    .buttonStyle(SocialPillButtonStyle(kind: .primary, height: 54))
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) { MayaAvatar(size: 32); Text("How it works").font(.system(size: 15, weight: .bold)) }
                    step(1, "blue", "Maya reads your profile", "Company name, goal, and what you sell. That’s all she needs to build a strategy.")
                    step(2, "violet", "She plans the calendar", "A post every day, about three weeks ahead, across your channels.")
                    step(3, "green", "You check in when you want", "Posts approve themselves 6 hours after she drafts them, unless you hold them.")
                }
                .padding(20)
                .background(SocialTheme.surface, in: RoundedRectangle(cornerRadius: 28))
            }
            .padding(20)
        }
    }

    private func step(_ number: Int, _ tint: String, _ title: String, _ text: String) -> some View {
        let colors = SocialTheme.tint(tint)
        return HStack(alignment: .top, spacing: 12) {
            Text("\(number)").font(.system(size: 14, weight: .bold)).frame(width: 30, height: 30).background(colors.bg, in: Circle()).foregroundStyle(colors.fg)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(SocialTheme.text)
                Text(text).font(.system(size: 14)).foregroundStyle(SocialTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(SocialTheme.bg, in: RoundedRectangle(cornerRadius: 22))
    }
}
