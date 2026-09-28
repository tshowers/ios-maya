import Combine
import Foundation
import StoreKit
import TODDEntitlementKit

/// Wraps TODDEntitlementKit the way AuthService wraps TODDAuthKit's
/// HostedLogin - see network-ios's EntitlementService for the fuller doc
/// comment on the pattern. Same shape here, productKey "maya" - the one
/// difference from the other apps is what this *gates*: purchase doesn't
/// lock the whole app, it unlocks personalization (see ChatViewModel,
/// which drives its `isSignedIn`/hydration off `isEntitled`, not just
/// sign-in, and ChatView's `.notEntitled` banner state).
@MainActor
final class EntitlementService: ObservableObject {
    @Published private(set) var isEntitled = false
    @Published private(set) var isLoadingEntitlement = true
    @Published private(set) var products: [Product] = []
    @Published private(set) var isPurchasing = false
    @Published var errorMessage: String?

    private let apiClient: MayaAppStoreClient
    private let authService: AuthService
    private let config: AppConfig
    private var transactionObserverTask: Task<Void, Never>?
    private var authSubscription: AnyCancellable?
    private var lastSeenUserId: String?

    init(apiClient: MayaAppStoreClient, authService: AuthService, config: AppConfig) {
        self.apiClient = apiClient
        self.authService = authService
        self.config = config
        self.lastSeenUserId = authService.userId

        transactionObserverTask = TransactionObserver.start { [weak self] _ in
            await self?.refreshEntitlement()
        }

        authSubscription = authService.$currentUser
            .map { $0?.uid }
            .removeDuplicates()
            .sink { [weak self] uid in
                guard let self, uid != self.lastSeenUserId else { return }
                self.lastSeenUserId = uid
                self.reset()
            }
    }

    deinit {
        transactionObserverTask?.cancel()
    }

    func reset() {
        isEntitled = false
        isLoadingEntitlement = true
        products = []
        errorMessage = nil
    }

    private var configuredProductIds: [String] {
        [config.mayaProductId].filter { !$0.isEmpty }
    }

    func loadProducts() async {
        guard !configuredProductIds.isEmpty else {
            errorMessage = "Maya's App Store subscription isn't configured yet."
            return
        }

        do {
            products = try await PurchaseManager.fetchProducts(productIds: configuredProductIds)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshEntitlement() async {
        isLoadingEntitlement = true
        defer { isLoadingEntitlement = false }

        do {
            isEntitled = try await apiClient.fetchAppStoreEntitlement().active
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func purchase(_ product: Product) async {
        guard let uid = authService.userId else { return }
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }

        do {
            let token = Self.appAccountToken(for: uid)
            try await apiClient.linkAppStorePurchase(appAccountToken: token.uuidString)
            try await PurchaseManager.purchase(product, appAccountToken: token)
            await refreshEntitlement()
        } catch PurchaseError.userCancelled {
            // Not an error worth surfacing.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restorePurchases() async {
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }

        do {
            try await PurchaseManager.restorePurchases()
            await refreshEntitlement()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func appAccountToken(for uid: String) -> UUID {
        let key = "maya.appAccountToken.\(uid)"
        if let stored = UserDefaults.standard.string(forKey: key), let uuid = UUID(uuidString: stored) {
            return uuid
        }
        let generated = UUID()
        UserDefaults.standard.set(generated.uuidString, forKey: key)
        return generated
    }
}
