import Foundation

enum MayaAppStoreError: LocalizedError {
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server response could not be understood."
        case .httpError(let code):
            return "The server returned HTTP \(code)."
        }
    }
}

/// Talks to `todd-backend`'s /api/app-store/* endpoints (appStoreRoutes.js).
/// Separate from MarketingDirectorAPIClient (Maya's chat client, which uses a
/// shared static API key, not a verified token) since the App Store
/// endpoints require a real verified Firebase ID token - same reasoning as
/// pulse-ios's PulseAppStoreClient.
final class MayaAppStoreClient {
    private let config: AppConfig
    private let authService: AuthService
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(config: AppConfig, authService: AuthService) {
        self.config = config
        self.authService = authService
    }

    func linkAppStorePurchase(appAccountToken: String) async throws {
        let payload = AppStoreLinkRequest(appAccountToken: appAccountToken, productKey: "maya")
        let url = config.apiBaseURL.appending(path: "app-store/link")
        _ = try await authorizedRequest(method: "POST", url: url, body: try encoder.encode(payload))
    }

    /// Sends a StoreKit transaction's signed JWS right after a purchase or
    /// restore; the backend verifies Apple's signature and returns the fresh
    /// entitlement - an immediate unlock that doesn't depend on Apple's
    /// server notification arriving (TestFlight renews about daily).
    func submitAppStoreTransaction(signedTransaction: String) async throws -> AppStoreEntitlement {
        let url = config.apiBaseURL.appending(path: "app-store/transactions/maya")
        let body = try encoder.encode(AppStoreTransactionRequest(signedTransaction: signedTransaction))
        let data = try await authorizedRequest(method: "POST", url: url, body: body)
        return try decoder.decode(AppStoreEntitlementEnvelope.self, from: data).entitlement
    }

    func fetchAppStoreEntitlement() async throws -> AppStoreEntitlement {
        let url = config.apiBaseURL.appending(path: "app-store/entitlement/maya")
        let data = try await authorizedRequest(method: "GET", url: url)
        return try decoder.decode(AppStoreEntitlementEnvelope.self, from: data).entitlement
    }

    private func authorizedRequest(method: String, url: URL, body: Data? = nil) async throws -> Data {
        let idToken = try await authService.freshIdToken()

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MayaAppStoreError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw MayaAppStoreError.httpError(httpResponse.statusCode)
        }

        return data
    }
}
