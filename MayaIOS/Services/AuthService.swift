import Foundation
import FirebaseAuth
import FirebaseFirestore
import TODDAuthKit

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

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in to connect Maya to your TODD account."
        }
    }
}
