import Foundation

/// Maya Social's API shapes (todd-backend/functions/mayaSocial/routes.js),
/// the same ones social.taliferro.tech uses (src/app/maya-social/api.ts).

struct SocialEnvelope<T: Decodable>: Decodable {
    let success: Bool
    let data: T
}

struct SocialErrorBody: Decodable {
    let error: String?
    let message: String?
    let missing: [String]?
    let check: PostCheck?
}

struct SocialProduct: Codable, Hashable {
    var id: String?
    var name: String
    var description: String
}

struct SocialProfile: Codable {
    var companyName: String
    var companyGoal: String
    var timezone: String?
    var products: [SocialProduct]
    var audience: String
    var location: String
    var website: String
    var tones: [String]
}

struct Pillar: Codable, Hashable {
    let key: String
    let name: String
    let share: Int
    let description: String
    let maxOneIn: Int
    let tint: String
}

struct SocialChannel: Codable, Hashable {
    let key: String
    let name: String
    let role: String
    let perWeek: Int
}

struct SocialStrategy: Codable {
    let goal: String
    let pillars: [Pillar]
    let channels: [SocialChannel]
    let autoApproveHours: Int
    let builtAt: String
    let approvedAt: String?
    let reason: String?
}

struct SocialOverview: Decodable {
    let entitled: Bool
    let onboardedAt: String?
    let autoApproveHours: Int?
    let timeZone: String?
    let today: String?
    let profile: SocialProfile?
    let missing: [String]?
    let strategy: SocialStrategy?
    let pendingStrategy: SocialStrategy?
    let plannedThrough: String?
    let nextPlanDate: String?
    let connectedChannels: [String]?
    let channels: [String: String]?
}

enum PostStatus: String, Codable {
    case planned, drafted, needs_review, approved, on_hold, posted, expired

    var label: String {
        switch self {
        case .planned: return "Planned"
        case .drafted: return "Drafted"
        case .needs_review: return "Needs review"
        case .approved: return "Approved"
        case .on_hold: return "On hold"
        case .posted: return "Posted"
        case .expired: return "Expired"
        }
    }

    var isActive: Bool { ![.posted, .expired].contains(self) }
}

struct SocialPost: Codable, Identifiable, Hashable {
    let id: String
    let pillar: String
    let title: String
    let body: String
    let channels: [String]
    let slotDate: String
    let time: String
    let slotAt: String
    let pinned: Bool
    let status: PostStatus
    let source: String?
    let autoApproveAt: String?
    let reviewOpensAt: String?
    let rewriteCount: Int?
    let holdCount: Int?
    let movedBackDays: Int
}

struct PostSlot: Codable, Hashable {
    let slotDate: String
    let time: String
}

struct PostMove: Codable, Hashable {
    let id: String
    let from: String
    let to: String
    let title: String?
}

struct PostVersion: Codable, Hashable {
    let title: String
    let body: String
}

struct PostCheck: Codable {
    let aligned: Bool
    let pillar: String
    let reasons: [String]
    let version: PostVersion?
    let slot: PostSlot?
    let moved: [PostMove]
    let placementError: String?
}

struct NewSocialPost: Encodable {
    var body: String
    var channels: [String]
    var pinned: Bool
    var slotDate: String?
    var time: String?
}

struct CreatedPost: Decodable {
    let post: SocialPost
    let moved: [PostMove]
}
