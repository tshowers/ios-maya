import Foundation

/// Body for `POST /api/app-store/transactions/maya` - a StoreKit
/// transaction's signed JWS, re-verified server-side.
struct AppStoreTransactionRequest: Encodable {
    let signedTransaction: String
}

struct AppStoreLinkRequest: Encodable {
    let appAccountToken: String
    let productKey: String
}

struct AppStoreEntitlementRecord: Codable {
    let productId: String
    let originalTransactionId: String
    let status: String
    let expiresDate: Double?
}

struct AppStoreEntitlement: Codable {
    let active: Bool
    let records: [AppStoreEntitlementRecord]
}

struct AppStoreEntitlementEnvelope: Codable {
    let success: Bool
    let entitlement: AppStoreEntitlement
}
