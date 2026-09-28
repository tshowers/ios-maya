import Foundation

enum MarketingDirectorAPIError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case emptyReply

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server response could not be understood."
        case .httpError(let code):
            return "The server returned HTTP \(code)."
        case .emptyReply:
            return "Maya did not return a usable reply."
        }
    }
}

/// Mirrors `public-marketing-director.service.ts`'s `askDirector`. This
/// endpoint is guarded by a single shared static bearer key server-side
/// (`TALIFERRO_TECH` in `todd-backend/functions/open-ai.js`), the same key
/// every web visitor uses whether signed in or not — it does no tenant
/// lookup of its own, so no `X-Tenant-Id`/`X-User-Id` headers are needed.
final class MarketingDirectorAPIClient {
    private let config: AppConfig
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(config: AppConfig) {
        self.config = config
    }

    func askDirector(
        message: String,
        history: [ChatMessage],
        workspaceContext: WorkspaceContext?
    ) async throws -> AdviceResponse {
        let requestBody = AdviceRequest(
            message: message.trimmingCharacters(in: .whitespacesAndNewlines),
            accessMode: "free",
            workspaceContext: workspaceContext,
            history: history.suffix(10).map { AdviceHistoryItem(role: $0.role.rawValue, content: $0.content) }
        )

        var urlRequest = URLRequest(url: config.apiBaseURL.appending(path: "marketing-director/advice"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try encoder.encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MarketingDirectorAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw MarketingDirectorAPIError.httpError(httpResponse.statusCode)
        }

        let envelope = try decoder.decode(AdviceEnvelope.self, from: data)
        guard !envelope.response.reply.isEmpty else {
            throw MarketingDirectorAPIError.emptyReply
        }

        return envelope.response
    }
}
