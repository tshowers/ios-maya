import Foundation
import FirebaseFirestore

/// Raw fields read from `tenants/{tenantId}/contacts/{uid}` — see
/// `contact.model.ts` for the full (much larger) shape; this is only the
/// slice `marketing-director-session.component.ts` actually reads.
struct ContactSnapshot {
    var firstName = ""
    var lastName = ""
    var profession = ""
    var jobDescriptionForTODD = ""
    var companyName = ""
    var companyDescription = ""
    var companyGoal = ""
    var companyValueProp = ""
}

/// Mirrors the Firestore reads in `frontend/src/app/services/user.service.ts`
/// (`getLoggedInContactInfo` → `tenants/{tenantId}/contacts/{uid}`) plus the
/// summary-building logic in `marketing-director-session.component.ts`
/// (`buildBusinessSummary`/`buildMissionSummary`, lines 608-642).
final class WorkspaceContextService {
    private let firestore = Firestore.firestore()

    func fetchContact(tenantId: String, uid: String) async -> ContactSnapshot? {
        guard !tenantId.isEmpty, !uid.isEmpty else { return nil }

        do {
            let document = try await firestore
                .collection("tenants").document(tenantId)
                .collection("contacts").document(uid)
                .getDocument()

            guard let data = document.data() else { return nil }
            let company = data["company"] as? [String: Any] ?? [:]

            return ContactSnapshot(
                firstName: data["firstName"] as? String ?? "",
                lastName: data["lastName"] as? String ?? "",
                profession: data["profession"] as? String ?? "",
                jobDescriptionForTODD: data["jobDescriptionForTODD"] as? String ?? "",
                companyName: company["name"] as? String ?? "",
                companyDescription: company["description"] as? String ?? "",
                companyGoal: company["goal"] as? String ?? "",
                companyValueProp: company["valueProp"] as? String ?? ""
            )
        } catch {
            return nil
        }
    }

    /// Raw fields sent to `/marketing-director/advice` as `workspaceContext`
    /// — mirrors `buildDirectorWorkspaceContext` in the web component.
    func buildWorkspaceContext(from contact: ContactSnapshot?, operatorName: String) -> WorkspaceContext {
        var context = WorkspaceContext()
        guard let contact else { return context }

        context.companyName = contact.companyName
        context.companyDescription = contact.companyDescription
        context.mission = contact.companyGoal
        context.offerSummary = !contact.companyValueProp.isEmpty ? contact.companyValueProp : contact.jobDescriptionForTODD
        context.operatorName = operatorName
        return context
    }

    /// Human-readable "I understand your business" sentence used in the
    /// signed-in intro message — mirrors `buildBusinessSummary` +
    /// `buildMissionSummary`, in the same priority order.
    func buildIntroContextSummary(from contact: ContactSnapshot?) -> String {
        guard let contact else { return "" }
        let businessSummary = buildBusinessSummary(contact)
        let missionSummary = buildMissionSummary(contact)
        return [businessSummary, missionSummary].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func buildBusinessSummary(_ contact: ContactSnapshot) -> String {
        if !contact.companyName.isEmpty, !contact.companyDescription.isEmpty {
            return "You run \(contact.companyName), and \(ensureSentence(contact.companyDescription))"
        }
        if !contact.jobDescriptionForTODD.isEmpty {
            return "I understand your role as \(ensureSentenceFragment(contact.jobDescriptionForTODD))."
        }
        if !contact.profession.isEmpty {
            return "I understand that you work in \(ensureSentenceFragment(contact.profession))."
        }
        if !contact.companyName.isEmpty, !contact.companyValueProp.isEmpty {
            return "You run \(contact.companyName), and your offer is \(ensureSentenceFragment(contact.companyValueProp))."
        }
        if !contact.companyName.isEmpty {
            return "You run \(contact.companyName)."
        }
        return ""
    }

    private func buildMissionSummary(_ contact: ContactSnapshot) -> String {
        guard !contact.companyGoal.isEmpty else { return "" }
        return "Your mission right now is \(ensureSentenceFragment(contact.companyGoal))."
    }

    private func ensureSentence(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?") ? trimmed : "\(trimmed)."
    }

    private func ensureSentenceFragment(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?") {
            trimmed.removeLast()
        }
        return trimmed
    }
}
