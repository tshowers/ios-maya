import SwiftUI
import TODDAuthKit

/// Mirrors the "cockpit" redesign of `marketing-director-session.component.html`
/// / `.css`: Maya logo + "Marketing advice" eyebrow, a rounded welcome
/// composer, three short chip prompts, TODD-navy message bubbles that adapt
/// to light/dark, and a pinned compact composer once the conversation has
/// started. Bottom tab navigation (Home/Talk/Status/Plan/More) and the
/// all-apps grid are web-only for now — this app has no other screens for
/// them to point at yet. Unlike `pulse-ios`, the whole screen is never gated
/// behind sign-in — `SignInView` and `BiometricLockView` are sheets reachable
/// from here, not something `RootView` swaps in for.
struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var authService: AuthService
    @ObservedObject var entitlementService: EntitlementService
    @State private var showSignIn = false
    @State private var showBiometricLock = false
    @State private var showPaywall = false

    private static let chipPrompts = ["Sharpen my message", "Find my best audience", "Clarify my offer"]

    private enum AuthDisplayState {
        case signedOut
        case locked
        case checkingEntitlement
        case notEntitled
        case unlocked
    }

    private var authDisplayState: AuthDisplayState {
        if authService.currentUser == nil { return .signedOut }
        if !authService.sessionGate.isUnlocked { return .locked }
        if entitlementService.isLoadingEntitlement { return .checkingEntitlement }
        if !entitlementService.isEntitled { return .notEntitled }
        return .unlocked
    }

    private var hasUserMessages: Bool {
        viewModel.messages.contains { $0.role == .user }
    }

    var body: some View {
        ZStack {
            MayaTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                switch authDisplayState {
                case .signedOut: signInBanner
                case .locked: unlockBanner
                case .checkingEntitlement: EmptyView()
                case .notEntitled: subscribeBanner
                case .unlocked: EmptyView()
                }

                if hasUserMessages {
                    messageList
                } else {
                    welcomeSection
                }

                if !viewModel.errorMessage.isEmpty {
                    Text(viewModel.errorMessage)
                        .font(.caption)
                        .foregroundStyle(MayaTheme.muted)
                        .padding(.horizontal)
                        .padding(.bottom, 6)
                }

                if hasUserMessages {
                    compactComposer
                }
            }
        }
        .sheet(isPresented: $showSignIn) {
            SignInView(onSignedIn: { showSignIn = false })
        }
        .sheet(isPresented: $showBiometricLock) {
            BiometricLockView(reason: "Unlock to restore your TODD session.") {
                authService.sessionGate.markUnlocked()
                showBiometricLock = false
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(entitlementService: entitlementService)
        }
    }

    // MARK: - Auth banners

    private var signInBanner: some View {
        Button {
            showSignIn = true
        } label: {
            HStack {
                Image(systemName: "person.crop.circle.badge.plus")
                Text("Sign in to connect Maya to your TODD account")
                    .font(.caption)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
            }
            .foregroundStyle(MayaTheme.text)
            .padding(10)
            .background(MayaTheme.accent.opacity(0.12))
        }
        .buttonStyle(.plain)
    }

    private var subscribeBanner: some View {
        Button {
            showPaywall = true
        } label: {
            HStack {
                Image(systemName: "sparkles")
                Text("Subscribe to unlock personalization")
                    .font(.caption)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
            }
            .foregroundStyle(MayaTheme.text)
            .padding(10)
            .background(MayaTheme.accent.opacity(0.12))
        }
        .buttonStyle(.plain)
    }

    private var unlockBanner: some View {
        Button {
            showBiometricLock = true
        } label: {
            HStack {
                Image(systemName: "faceid")
                Text("Unlock to restore your TODD session")
                    .font(.caption)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
            }
            .foregroundStyle(MayaTheme.text)
            .padding(10)
            .background(MayaTheme.accent.opacity(0.12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Welcome state (`.maya-welcome`)

    private var welcomeSection: some View {
        VStack {
            Spacer(minLength: 12)

            VStack(spacing: 18) {
                Image("MayaLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 220, maxHeight: 88)

                Text("MARKETING ADVICE")
                    .font(.system(size: 12, weight: .heavy))
                    .tracking(2.4)
                    .foregroundStyle(MayaTheme.accent)

                welcomeComposer

                MayaFlowLayout(spacing: 10) {
                    ForEach(Self.chipPrompts, id: \.self) { chip in
                        chipButton(chip)
                    }
                }
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 12)
        }
    }

    private var welcomeComposer: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .topLeading) {
                if viewModel.prompt.isEmpty {
                    Text("Ask Maya...")
                        .foregroundStyle(MayaTheme.muted)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $viewModel.prompt)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(MayaTheme.text)
                    .frame(minHeight: 100, maxHeight: 140)
            }

            Button {
                Task { await viewModel.sendMessage() }
            } label: {
                HStack(spacing: 10) {
                    Text(viewModel.sending ? "…" : "Ask Maya")
                    if !viewModel.sending {
                        Image(systemName: "arrow.up.right")
                            .font(.subheadline.weight(.bold))
                    }
                }
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(MayaTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 15))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.sending)
        }
        .padding(14)
        .background(MayaTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 25))
        .overlay(RoundedRectangle(cornerRadius: 25).stroke(MayaTheme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 20, y: 10)
    }

    private func chipButton(_ label: String) -> some View {
        Button {
            Task { await viewModel.sendMessage(preset: label) }
        } label: {
            HStack(spacing: 8) {
                Text(label)
                Text("↗").foregroundStyle(MayaTheme.accent)
            }
            .font(.subheadline)
            .foregroundStyle(MayaTheme.text)
            .padding(.horizontal, 15)
            .padding(.vertical, 11)
            .background(MayaTheme.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(MayaTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.sending)
    }

    // MARK: - Conversation state (`.maya-messages`)

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                    if viewModel.sending {
                        thinkingBubble
                            .id("maya-thinking")
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.messages.count) { _, _ in scrollToBottom(proxy: proxy) }
            .onChange(of: viewModel.sending) { _, sending in if sending { scrollToBottom(proxy: proxy) } }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation {
            if viewModel.sending {
                proxy.scrollTo("maya-thinking", anchor: .bottom)
            } else if let lastId = viewModel.messages.last?.id {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
    }

    private var thinkingBubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MAYA")
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.5)
                .foregroundStyle(MayaTheme.muted)
            HStack(spacing: 6) {
                MayaThinkingDots()
                Text("Maya is thinking…")
                    .font(.subheadline)
                    .foregroundStyle(MayaTheme.muted)
            }
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MayaTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(MayaTheme.border, lineWidth: 1))
    }

    private var compactComposer: some View {
        HStack(spacing: 8) {
            TextField("Ask Maya...", text: $viewModel.prompt, axis: .vertical)
                .lineLimit(1...4)
                .foregroundStyle(MayaTheme.text)
                .tint(MayaTheme.accent)

            Button {
                viewModel.resetConversation()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .foregroundStyle(MayaTheme.muted)
                    .frame(width: 38, height: 38)
                    .background(MayaTheme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.sending)
            .accessibilityLabel("Reset conversation")

            Button {
                Task { await viewModel.sendMessage() }
            } label: {
                Group {
                    if viewModel.sending {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.up.right")
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 44, height: 44)
                .background(MayaTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 13))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.sending)
            .accessibilityLabel("Ask Maya")
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 9)
        .background(MayaTheme.surface.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 19))
        .overlay(RoundedRectangle(cornerRadius: 19).stroke(MayaTheme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}

/// Ports `.maya-message` / `.maya-message--user`: a small uppercase role
/// label over the content, right-aligned and accent-tinted for the user.
private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            Text(message.role == .director ? "MAYA" : "YOU")
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.5)
                .foregroundStyle(MayaTheme.muted)
            Text(Self.linkified(message.content))
                .font(.body)
                .foregroundStyle(MayaTheme.text)
                .tint(MayaTheme.accent)
                .multilineTextAlignment(message.role == .user ? .trailing : .leading)
        }
        .padding(16)
        .background(message.role == .user ? MayaTheme.userBubbleBackground : MayaTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(message.role == .user ? MayaTheme.userBubbleBorder : MayaTheme.border, lineWidth: 1)
        )
        .frame(maxWidth: 300, alignment: message.role == .user ? .trailing : .leading)
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    /// Maya's replies are conversational text, not Markdown - a plain
    /// `Text(content)` never made a URL she mentions tappable at all.
    /// `NSDataDetector` finds URLs anywhere in the string and marks them
    /// as `.link` runs, so tapping one goes through the system's normal
    /// URL-opening path - which is exactly what makes Universal Links
    /// work later (open the native app if it's installed and associated
    /// with that domain, Safari otherwise) with no extra code here.
    private static func linkified(_ content: String) -> AttributedString {
        let mutable = NSMutableAttributedString(string: content)
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let matches = detector.matches(in: content, range: NSRange(location: 0, length: (content as NSString).length))
            for match in matches {
                if let url = match.url {
                    mutable.addAttribute(.link, value: url, range: match.range)
                }
            }
        }
        return (try? AttributedString(mutable, including: \.foundation)) ?? AttributedString(content)
    }
}
