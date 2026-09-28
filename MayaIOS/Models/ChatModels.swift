import Foundation

enum ChatRole: String, Codable {
    case user
    case director
}

struct ChatMessage: Identifiable, Equatable {
    let id: String
    let role: ChatRole
    let content: String

    init(id: String = UUID().uuidString, role: ChatRole, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}

/// Mirrors `PublicMarketingDirectorWorkspaceContext` in
/// `public-marketing-director.service.ts`. The `/marketing-director/advice`
/// endpoint expects this exact shape; fields the deferred execution-actions
/// system would populate (`availableSystems`, work-item titles, active plan)
/// are always sent empty/false in v1 rather than omitted, since the backend
/// prompt-builder expects the full shape.
struct WorkspaceContext: Encodable {
    var companyName: String = ""
    var companyDescription: String = ""
    var mission: String = ""
    var offerSummary: String = ""
    var operatorName: String = ""
    var accessModeLabel: String = "logged_in_advice"
    var hasActivePlan: Bool = false
    var availableSystems: [String] = []
    var currentWorkTitles: [String] = []
    var pendingApprovalTitles: [String] = []
    var completedWorkTitles: [String] = []
}

struct AdviceHistoryItem: Encodable {
    let role: String
    let content: String
}

struct AdviceRequest: Encodable {
    let message: String
    let accessMode: String
    let workspaceContext: WorkspaceContext?
    let history: [AdviceHistoryItem]
}

/// Decode-only stub for the execution-actions system (`create_document`,
/// `create_move`, `create_survey`, `create_response_flow`, `send_email`).
/// v1 never acts on these — this only exists so decoding the advice response
/// doesn't break when the backend includes them.
struct SystemAction: Decodable {
    let type: String
}

struct AdviceResponse: Decodable {
    let reply: String
    let executionIntent: Bool
    let systemActions: [SystemAction]?
}

struct AdviceEnvelope: Decodable {
    let response: AdviceResponse
}
