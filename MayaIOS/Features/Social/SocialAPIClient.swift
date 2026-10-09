import Foundation

enum SocialAPIError: LocalizedError {
    case invalidResponse
    /// The server said no, with its code and message (and, for some codes,
    /// what's missing or Maya's check of a post).
    case server(status: Int, body: SocialErrorBody?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server response could not be understood."
        case .server(let status, let body):
            return body?.message ?? "The server returned HTTP \(status)."
        }
    }

    var code: String? {
        if case .server(_, let body) = self { return body?.error }
        return nil
    }

    var check: PostCheck? {
        if case .server(_, let body) = self { return body?.check }
        return nil
    }
}

/// Maya Social's /api/maya-social/* endpoints. Every call carries a verified
/// Firebase ID token, like MayaAppStoreClient.
final class SocialAPIClient {
    private let baseURL: URL
    private let authService: AuthService
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(config: AppConfig, authService: AuthService) {
        self.baseURL = config.apiBaseURL.appending(path: "maya-social")
        self.authService = authService
    }

    func overview() async throws -> SocialOverview {
        try await request("GET", "overview")
    }

    func onboard(autoApproveHours: Int) async throws -> SocialOverview {
        try await request("POST", "onboard", body: ["autoApproveHours": autoApproveHours])
    }

    func setAutoApproveHours(_ hours: Int) async throws -> SocialOverview {
        try await request("PUT", "settings", body: ["autoApproveHours": hours])
    }

    func saveProfile(_ profile: SocialProfile) async throws -> SocialOverview {
        try await request("PATCH", "profile", body: ["profile": profile])
    }

    func generateStrategy() async throws -> SocialStrategy {
        try await request("POST", "strategy/generate", body: [String: String]())
    }

    func approveStrategy() async throws -> SocialOverview {
        try await request("POST", "strategy/approve", body: [String: String]())
    }

    func discardPendingStrategy() async throws -> SocialOverview {
        try await request("DELETE", "strategy/pending")
    }

    func posts(from: String, to: String) async throws -> [SocialPost] {
        try await request("GET", "posts", query: [URLQueryItem(name: "from", value: from), URLQueryItem(name: "to", value: to)])
    }

    func check(_ post: NewSocialPost) async throws -> PostCheck {
        try await request("POST", "posts/check", body: post)
    }

    func create(_ post: NewSocialPost) async throws -> CreatedPost {
        try await request("POST", "posts", body: post)
    }

    func edit(_ id: String, title: String, body: String) async throws -> SocialPost {
        try await request("PUT", "posts/\(id)", body: ["title": title, "body": body])
    }

    func approve(_ id: String) async throws -> SocialPost {
        try await request("POST", "posts/\(id)/approve", body: [String: String]())
    }

    func undoApprove(_ id: String) async throws -> SocialPost {
        try await request("POST", "posts/\(id)/undo-approve", body: [String: String]())
    }

    func hold(_ id: String) async throws -> SocialPost {
        try await request("POST", "posts/\(id)/hold", body: [String: String]())
    }

    // MARK: -

    private func request<T: Decodable>(_ method: String, _ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await send(method, path, query: query, body: nil)
    }

    private func request<T: Decodable, B: Encodable>(_ method: String, _ path: String, body: B) async throws -> T {
        try await send(method, path, query: [], body: try encoder.encode(body))
    }

    private func send<T: Decodable>(_ method: String, _ path: String, query: [URLQueryItem], body: Data?) async throws -> T {
        let idToken = try await authService.freshIdToken()
        var url = baseURL.appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.timeoutInterval = 180 // generating a strategy or a rewrite takes a while
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw SocialAPIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw SocialAPIError.server(status: http.statusCode, body: try? decoder.decode(SocialErrorBody.self, from: data))
        }
        return try decoder.decode(SocialEnvelope<T>.self, from: data).data
    }
}
