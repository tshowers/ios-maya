import Foundation
import TODDAwardsKit

/// Maya's awards on the shared, account-synced TODDAwardsKit - the same set
/// on iPhone and iPad, each award celebrated once (the server decides
/// what's new). Question counts come from `/getting-started/maya`, so they
/// can't drift from the real conversation.
enum MayaAwards {
    static let ladder: [Award] = [
        Award(id: "first-question", title: "The Curious", copy: "You asked. That's where every good plan starts.", symbol: "lightbulb.fill"),
        Award(id: "committer", title: "The Committer", copy: "You connected Maya to your business. Now it's personal.", symbol: "checkmark.seal.fill"),
        Award(id: "introduction", title: "The Introduction", copy: "Your profile is complete. Maya knows who she's advising.", symbol: "person.text.rectangle.fill"),
        Award(id: "connector", title: "The Connector", copy: "Your other TODD apps give Maya more to work with.", symbol: "link"),
        Award(id: "all-set", title: "The Regular", copy: "Getting Started, finished. You know your way around.", symbol: "star.circle.fill"),
        Award(id: "habit", title: "The Habit", copy: "Ten questions. Maya's part of how you work now.", symbol: "flame.fill"),
        Award(id: "strategist", title: "The Strategist", copy: "Fifty questions. You don't guess - you plan.", symbol: "chart.line.uptrend.xyaxis"),
        Award(id: "director", title: "The Director", copy: "A hundred questions. Maya works for you now.", symbol: "crown.fill", hidden: true),
    ]

    @MainActor
    static func makeService(authService: AuthService) -> AwardsService {
        AwardsService(
            appName: "Maya",
            ladder: ladder,
            api: AwardsAPI(
                baseURL: AppConfig.fromBundle().apiBaseURL,
                product: "maya",
                idToken: { @MainActor [weak authService] in
                    guard let authService else { throw AuthServiceError.notSignedIn }
                    return try await authService.freshIdToken()
                }
            )
        )
    }

    /// `GET /getting-started/maya`, read for the award counts - the
    /// checklist page itself is TODDProfileKit's GettingStartedView.
    static func loadProgress(authService: AuthService) async -> MayaProgress? {
        guard let idToken = try? await authService.freshIdToken() else { return nil }
        var request = URLRequest(url: AppConfig.fromBundle().apiBaseURL.appending(path: "getting-started/maya"))
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
        return try? JSONDecoder().decode(MayaProgressEnvelope.self, from: data).data
    }
}

/// Maya's record points - each checked at the moment it could become true.
extension AwardsService {
    /// A question sent - works signed out too (celebrated here, synced
    /// silently after sign-in).
    func recordQuestionAsked() {
        unlock("first-question")
    }

    func recordSignedUp() {
        unlock("committer")
    }

    func recordProgress(_ progress: MayaProgress) {
        if progress.steps.first(where: { $0.id == "profile" })?.done == true { unlock("introduction") }
        if progress.allDone { unlock("all-set") }
        guard let counts = progress.counts else { return }
        if counts.questions >= 1 { unlock("first-question") }
        if counts.questions >= 10 { unlock("habit") }
        if counts.questions >= 50 { unlock("strategist") }
        if counts.questions >= 100 { unlock("director") }
        if counts.otherApps >= 1 { unlock("connector") }
    }
}

struct MayaProgress: Decodable {
    struct Step: Decodable {
        let id: String
        let done: Bool
    }

    struct Counts: Decodable {
        let questions: Int
        let otherApps: Int
    }

    let steps: [Step]
    let allDone: Bool
    let counts: Counts?
}

struct MayaProgressEnvelope: Decodable {
    let data: MayaProgress
}
