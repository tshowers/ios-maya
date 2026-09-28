import Foundation
import FirebaseFirestore

/// Mirrors the conversation-persistence slice of `marketing-employee.service.ts`
/// (`createConversation`/`watchConversations`/`watchConversationMessages`/
/// `appendConversationMessage`) plus the "find or create the one session
/// conversation" logic in `marketing-director-session.component.ts`'s
/// `ensureWorkspaceSessionConnection`. Only active when signed in — signed-out
/// users get an ephemeral in-memory conversation the web app also falls back to.
///
/// v1 uses one-shot reads instead of the web app's live listener: nothing else
/// writes into this conversation in the deferred-execution-actions world, so
/// there's nothing to sync in real time yet.
final class ConversationStore {
    private let firestore = Firestore.firestore()
    private let employeeId = "marketing-employee" // DEFAULT_MARKETING_EMPLOYEE_ID
    private let conversationTitle = "Maya master marketing plan session"

    private func conversationsRef(tenantId: String) -> CollectionReference {
        firestore.collection("tenants").document(tenantId).collection("employee-conversations")
    }

    private func messagesRef(tenantId: String, conversationId: String) -> CollectionReference {
        conversationsRef(tenantId: tenantId).document(conversationId).collection("messages")
    }

    func findOrCreateConversation(tenantId: String) async -> String? {
        guard !tenantId.isEmpty else { return nil }

        do {
            let snapshot = try await conversationsRef(tenantId: tenantId)
                .whereField("employeeId", isEqualTo: employeeId)
                .order(by: "updatedAt", descending: true)
                .limit(to: 20)
                .getDocuments()

            if let existing = snapshot.documents.first(where: {
                (($0.data()["title"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == conversationTitle.lowercased()
            }) {
                return existing.documentID
            }

            let created = try await conversationsRef(tenantId: tenantId).addDocument(data: [
                "employeeId": employeeId,
                "employeeType": "marketing",
                "title": conversationTitle,
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ])
            return created.documentID
        } catch {
            return nil
        }
    }

    func loadMessages(tenantId: String, conversationId: String) async -> [ChatMessage] {
        guard !tenantId.isEmpty, !conversationId.isEmpty else { return [] }

        do {
            let snapshot = try await messagesRef(tenantId: tenantId, conversationId: conversationId)
                .order(by: "createdAt", descending: false)
                .limit(to: 200)
                .getDocuments()

            return snapshot.documents.compactMap { document in
                let data = document.data()
                guard let content = data["content"] as? String, !content.isEmpty else { return nil }
                let storedRole = (data["role"] as? String ?? "").lowercased()
                return ChatMessage(id: document.documentID, role: storedRole == "user" ? .user : .director, content: content)
            }
        } catch {
            return []
        }
    }

    func appendMessage(tenantId: String, conversationId: String, role: ChatRole, content: String) async {
        guard !tenantId.isEmpty, !conversationId.isEmpty, !content.isEmpty else { return }

        do {
            try await messagesRef(tenantId: tenantId, conversationId: conversationId).addDocument(data: [
                "role": role == .user ? "user" : "employee",
                "content": content,
                "relatedActionIds": [],
                "createdAt": FieldValue.serverTimestamp()
            ])
            try await conversationsRef(tenantId: tenantId).document(conversationId).updateData([
                "updatedAt": FieldValue.serverTimestamp()
            ])
        } catch {
            // Keep the live session moving even if shared persistence fails,
            // same fallback behavior as `appendWorkspaceMessage` on the web.
        }
    }
}
