import Foundation
import FirebaseAuth
import FirebaseFirestore
import TODDAuthKit
import TODDProfileKit

/// Mirrors `frontend/src/app/services/auth.service.ts`. Unlike `pulse-ios`
/// (where `tenantId` is just the Firebase UID), Maya needs the same
/// `users/{uid}.companyId` lookup the web app does in
/// `resolveAssignedTenantId`, since that's what `WorkspaceContextService` and
/// `ConversationStore` key everything under. Falls back to the uid itself
/// when the user has no `companyId` on file, same as the web app.
///
/// Sign-in is Sign in with Apple only (`TODDAuthKit.SignInWithAppleButtonView`)
/// — no password, no email link. `sessionGate` (also from `TODDAuthKit`)
/// tracks whether a silently-restored session still needs a fresh biometric
/// check before `ChatViewModel` hydrates personalization/history for it.
@MainActor
final class AuthService: ObservableObject {
    @Published private(set) var currentUser: User?
    @Published private(set) var isLoading = true
    @Published private(set) var tenantId: String?

    let sessionGate = SessionUnlockGate()
    private var handle: AuthStateDidChangeListenerHandle?
    private let firestore = Firestore.firestore()

    init() {
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            self.currentUser = user
            self.isLoading = false
            self.sessionGate.handleAuthStateChange(hasUser: user != nil)
            Task { await self.refreshTenantId() }
            // Retries a wizard profile save that failed on a previous launch.
            if user != nil {
                Task { await self.submitOnboardingProfileIfNeeded() }
            }
        }
    }

    deinit {
        if let handle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    var userId: String? { currentUser?.uid }
    var userEmail: String? { currentUser?.email }

    func signOut() throws {
        try Auth.auth().signOut()
        tenantId = nil
    }

    /// Fresh Firebase ID token for the App Store link/entitlement endpoints
    /// (appStoreRoutes.js), which require a real verified caller.
    func freshIdToken() async throws -> String {
        guard let user = currentUser else {
            throw AuthServiceError.notSignedIn
        }
        return try await user.getIDToken()
    }

    /// Calls the backend's get-or-create tenant/contact endpoint
    /// (`POST /api/mobile/auth/bootstrap`, mobileAuthRoutes.js) right after a
    /// fresh native sign-in - same as network-ios/docs-ios - so a brand-new
    /// Maya user has a TODD workspace and profile record, then saves the
    /// wizard's answers into it.
    func bootstrapTenant() async throws {
        let idToken = try await freshIdToken()
        var request = URLRequest(url: AppConfig.fromBundle().apiBaseURL.appending(path: "mobile/auth/bootstrap"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AuthServiceError.bootstrapFailed
        }
        tenantId = try JSONDecoder().decode(BootstrapResponse.self, from: data).tenantId
        await submitOnboardingProfileIfNeeded()
    }

    /// Where the wizard keeps name/role/company/goals until sign-in.
    static let profileStore = OnboardingProfileStore(storageKey: "maya.onboardingProfile", source: "maya-ios")

    /// Saves the wizard's answers to the TODD profile (blank fields only,
    /// best-effort; retried next launch if it fails).
    func submitOnboardingProfileIfNeeded() async {
        guard currentUser != nil else { return }
        await Self.profileStore.submitIfReady(
            baseURL: AppConfig.fromBundle().apiBaseURL,
            idToken: { [weak self] in
                guard let self else { throw AuthServiceError.notSignedIn }
                return try await self.freshIdToken()
            }
        )
    }

    var profileAPI: ProfileAPI {
        ProfileAPI(
            baseURL: AppConfig.fromBundle().apiBaseURL,
            idToken: { @MainActor [weak self] in
                guard let self else { throw AuthServiceError.notSignedIn }
                return try await self.freshIdToken()
            }
        )
    }

    private func refreshTenantId() async {
        guard let uid = currentUser?.uid else {
            tenantId = nil
            return
        }

        do {
            let snapshot = try await firestore.collection("users").document(uid).getDocument()
            let companyId = (snapshot.data()?["companyId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            tenantId = (companyId?.isEmpty == false ? companyId : nil) ?? uid
        } catch {
            tenantId = uid
        }
    }
}

enum AuthServiceError: LocalizedError {
    case notSignedIn
    case bootstrapFailed

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in to connect Maya to your TODD account."
        case .bootstrapFailed:
            return "Unable to set up your account. Please try again."
        }
    }
}

private struct BootstrapResponse: Decodable {
    let tenantId: String
}
