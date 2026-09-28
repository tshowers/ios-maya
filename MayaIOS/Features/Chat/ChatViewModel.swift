import Foundation
import Combine
import FirebaseAuth

/// Ports the relevant slice of `marketing-director-session.component.ts`.
/// Deliberately NOT ported: `maybePersistMasterPlan`,
/// `executeDirectorSystemActions`, and every `executeCreate*Action` —
/// the execution-actions system is milestone 2 (see `README.md`).
@MainActor
final class ChatViewModel: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published var prompt: String = ""
    @Published private(set) var sending = false
    @Published var errorMessage = ""
    @Published private(set) var starterPrompts: [String] = ChatViewModel.publicStarterPrompts
    @Published private(set) var composerPlaceholder: String = ChatViewModel.publicPlaceholder
    @Published private(set) var isSignedIn = false
    @Published private(set) var isHydrating = false

    private let apiClient: MarketingDirectorAPIClient
    private let authService: AuthService
    private let entitlementService: EntitlementService
    private let workspaceContextService: WorkspaceContextService
    private let conversationStore: ConversationStore

    private var tenantId: String?
    private var contact: ContactSnapshot?
    private var operatorName: String = ""
    private var conversationId: String?
    private var hydratedTenantId: String?
    private var entitlementCheckedForTenantId: String?
    private var cancellables = Set<AnyCancellable>()

    init(
        apiClient: MarketingDirectorAPIClient,
        authService: AuthService,
        entitlementService: EntitlementService,
        workspaceContextService: WorkspaceContextService,
        conversationStore: ConversationStore
    ) {
        self.apiClient = apiClient
        self.authService = authService
        self.entitlementService = entitlementService
        self.workspaceContextService = workspaceContextService
        self.conversationStore = conversationStore
        self.messages = [Self.buildPublicIntroMessage()]

        Publishers.CombineLatest4(
            authService.$currentUser,
            authService.$tenantId,
            authService.sessionGate.$isUnlocked,
            entitlementService.$isEntitled
        )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] user, tenantId, isUnlocked, isEntitled in
                Task { await self?.handleAuthChange(user: user, tenantId: tenantId, isUnlocked: isUnlocked, isEntitled: isEntitled) }
            }
            .store(in: &cancellables)
    }

    func sendMessage(preset: String? = nil) async {
        let text = (preset ?? prompt).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }

        errorMessage = ""
        sending = true
        prompt = ""

        let userMessage = ChatMessage(role: .user, content: text)
        let historyForRequest = messages
        messages.append(userMessage)
        await persistIfSignedIn(role: .user, content: text)

        do {
            let workspaceContext = isSignedIn
                ? workspaceContextService.buildWorkspaceContext(from: contact, operatorName: operatorName)
                : nil
            let response = try await apiClient.askDirector(
                message: text,
                history: historyForRequest,
                workspaceContext: workspaceContext
            )
            let reply = Self.normalizeDirectorReply(response.reply)
            messages.append(ChatMessage(role: .director, content: reply))
            await persistIfSignedIn(role: .director, content: reply)
        } catch {
            errorMessage = "She could not answer that right now. Please try again in a moment."
        }

        sending = false
    }

    /// Backs the compact composer's reset (↺) button, mirroring what
    /// `resetSession()` does visually on the web. Just clears the on-screen
    /// conversation back to the intro message — re-creating the backend
    /// workspace conversation the way the web does is out of scope here.
    func resetConversation() {
        guard !sending else { return }
        prompt = ""
        errorMessage = ""
        messages = [isSignedIn ? buildLoggedInIntroMessage() : Self.buildPublicIntroMessage()]
    }

    // MARK: - Auth hydration

    private func handleAuthChange(user: User?, tenantId: String?, isUnlocked: Bool, isEntitled: Bool) async {
        guard let user, let tenantId else {
            if isSignedIn {
                resetToSignedOutState()
            }
            entitlementCheckedForTenantId = nil
            return
        }

        // A silently-restored session (cold launch) needs a biometric check
        // before Maya hydrates personalization/history for it — ChatView
        // shows the "Unlock to restore your TODD session" affordance in the
        // meantime and chat keeps working as a guest. A fresh interactive
        // sign-in already arrives with `isUnlocked == true` (Face ID ran as
        // part of the Sign in with Apple prompt itself), so this never adds
        // an extra step there.
        guard isUnlocked else { return }

        // Kick off the entitlement check once per signed-in tenant -
        // EntitlementService.isLoadingEntitlement starts true, so ChatView's
        // `.checkingEntitlement` banner state covers the gap until this
        // resolves and this function runs again with the real isEntitled
        // value via the Combine subscription above.
        if entitlementCheckedForTenantId != tenantId {
            entitlementCheckedForTenantId = tenantId
            Task { await entitlementService.refreshEntitlement() }
        }

        // Purchase unlocks personalization, not sign-in alone - see
        // docs/app-store-exclusive-billing-plan.md's "Maya and Ask TODD"
        // section. Signed in but not entitled: chat keeps working as a
        // guest (isSignedIn stays false) until there's an entitlement to
        // hydrate personalization against.
        guard isEntitled else { return }

        guard tenantId != hydratedTenantId else { return }
        hydratedTenantId = tenantId
        self.tenantId = tenantId
        isSignedIn = true
        isHydrating = true

        let fetchedContact = await workspaceContextService.fetchContact(tenantId: tenantId, uid: user.uid)
        contact = fetchedContact
        operatorName = [fetchedContact?.firstName, fetchedContact?.lastName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let resolvedConversationId = await conversationStore.findOrCreateConversation(tenantId: tenantId)
        conversationId = resolvedConversationId

        var restoredMessages: [ChatMessage] = []
        if let resolvedConversationId {
            restoredMessages = await conversationStore.loadMessages(tenantId: tenantId, conversationId: resolvedConversationId)
        }

        if !restoredMessages.isEmpty {
            messages = restoredMessages
        } else {
            let intro = buildLoggedInIntroMessage()
            messages = [intro]
            await persistIfSignedIn(role: .director, content: intro.content)
        }

        starterPrompts = Self.loggedInSetupStarterPrompts
        composerPlaceholder = "Ask Maya to create your initial marketing plan, or paste in the plan you already have for analysis."
        isHydrating = false
    }

    private func resetToSignedOutState() {
        isSignedIn = false
        hydratedTenantId = nil
        tenantId = nil
        contact = nil
        conversationId = nil
        operatorName = ""
        starterPrompts = Self.publicStarterPrompts
        composerPlaceholder = Self.publicPlaceholder
        messages = [Self.buildPublicIntroMessage()]
    }

    private func persistIfSignedIn(role: ChatRole, content: String) async {
        guard isSignedIn, let tenantId, let conversationId else { return }
        await conversationStore.appendMessage(tenantId: tenantId, conversationId: conversationId, role: role, content: content)
    }

    private func buildLoggedInIntroMessage() -> ChatMessage {
        let contextSummary = workspaceContextService.buildIntroContextSummary(from: contact)
        let intro = "I understand you and the work you are building."
        let profileLine = contextSummary.isEmpty ? "" : " \(contextSummary)"
        let callToAction = " Would you like me to create your initial marketing plan, or paste in the marketing plan you already have so I can analyze it and make recommendations?"
        let content = "\(intro)\(profileLine)\(callToAction)".trimmingCharacters(in: .whitespacesAndNewlines)
        return ChatMessage(role: .director, content: content)
    }

    // MARK: - Static copy (mirrors the web component's builder methods)

    private static let publicStarterPrompts = [
        "I have a small budget and need better leads. Where would you focus first?",
        "My message feels too generic. How would you sharpen it?",
        "What campaign would you run first for a service business that needs traction?",
        "How do I know if my offer is clear enough to market well?"
    ]

    private static let loggedInSetupStarterPrompts = [
        "Create my initial marketing plan based on what you already know about my business.",
        "We do not have a real marketing plan yet. Create one now.",
        "I already have a marketing plan. I want to paste it in so you can analyze it.",
        "What should our first campaign be based on my mission?",
        "What are the biggest gaps in my current marketing foundation?"
    ]

    private static let publicPlaceholder = "Ask Maya about positioning, campaigns, messaging, or what to fix first."

    private static func buildPublicIntroMessage() -> ChatMessage {
        ChatMessage(
            role: .director,
            content: "I’m Maya. Tell me what you sell, who you want to reach, and what feels stuck in your marketing. I’ll help you figure out what matters first."
        )
    }

    // MARK: - Reply cleanup (ported verbatim from `normalizeDirectorReply`)

    private static func normalizeDirectorReply(_ content: String) -> String {
        var normalized = content

        normalized = normalized.replacingOccurrences(of: "\r", with: "")
        normalized = regexReplace(normalized, pattern: #"(^|\n)#{1,6}\s*"#, template: "$1")
        normalized = regexReplace(normalized, pattern: #"here(?: is|'s)\s+a\s+structured\s+outline\s*:"#, template: "Here's how I'd work it:", caseInsensitive: true)
        normalized = regexReplace(normalized, pattern: #"it could benefit from"#, template: "it needs", caseInsensitive: true)
        normalized = regexReplace(normalized, pattern: #"let'?s get this set up[.\s-]*i['’]ll take care of it now\.?"#, template: "I can draft that next, but it is not saved anywhere yet.", caseInsensitive: true)
        normalized = regexReplace(normalized, pattern: #"i['’]ll take care of it now\.?"#, template: "I can draft that next, but it is not saved anywhere yet.", caseInsensitive: true)
        normalized = regexReplace(normalized, pattern: #"i['’]ll handle it now\.?"#, template: "I can draft that next, but it is not saved anywhere yet.", caseInsensitive: true)
        normalized = regexReplace(normalized, pattern: #"would you like to implement these changes,? or do you want to brainstorm further around this messaging framework\?"#, template: "If you want, I can turn this into the actual homepage copy next.", caseInsensitive: true)
        normalized = regexReplace(normalized, pattern: #"let me know how you'd like to proceed\.?"#, template: "Pick the next move and I\u{2019}ll keep going.", caseInsensitive: true)
        normalized = regexReplace(normalized, pattern: #"\n{3,}"#, template: "\n\n")
        normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return normalized }

        let needsSpecificPrompt =
            regexTest(normalized, pattern: #"how you'd like to proceed"#, caseInsensitive: true) ||
            regexTest(normalized, pattern: #"what you want to prioritize first"#, caseInsensitive: true) ||
            regexTest(normalized, pattern: #"let me know how to proceed"#, caseInsensitive: true)

        guard needsSpecificPrompt else { return normalized }

        return """
        \(normalized)

        Pick one and I will keep moving:
        - Define the target audience first
        - Draft the affiliate and reseller program
        - Build the first campaign plan
        """
    }

    private static func regexReplace(_ input: String, pattern: String, template: String, caseInsensitive: Bool = false) -> String {
        var options: NSRegularExpression.Options = []
        if caseInsensitive { options.insert(.caseInsensitive) }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return input }
        let range = NSRange(input.startIndex..., in: input)
        return regex.stringByReplacingMatches(in: input, options: [], range: range, withTemplate: template)
    }

    private static func regexTest(_ input: String, pattern: String, caseInsensitive: Bool = false) -> Bool {
        var options: NSRegularExpression.Options = []
        if caseInsensitive { options.insert(.caseInsensitive) }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return false }
        let range = NSRange(input.startIndex..., in: input)
        return regex.firstMatch(in: input, options: [], range: range) != nil
    }
}
