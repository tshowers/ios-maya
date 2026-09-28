import SwiftUI
import StoreKit
import TODDEntitlementKit

/// Pushed as a page (no popups) when a signed-in user taps the "subscribe
/// to unlock personalization" banner in `ChatView`; Back returns to chat. Unlike the other apps' PaywallView,
/// this is dismissible without signing out - Maya's chat keeps working as a
/// guest either way, purchase only unlocks the personalized layer on top.
struct PaywallView: View {
    @ObservedObject var entitlementService: EntitlementService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
            VStack(spacing: 16) {
                Spacer()

                Text("Subscribe to Maya")
                    .font(.title2.bold())
                Text("An active subscription unlocks personalization - Maya sees your business context and remembers your conversations.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                if entitlementService.products.isEmpty {
                    ProgressView()
                        .padding(.top, 24)
                } else {
                    VStack(spacing: 12) {
                        ForEach(entitlementService.products) { product in
                            Button {
                                Task {
                                    await entitlementService.purchase(product)
                                    if entitlementService.isEntitled { dismiss() }
                                }
                            } label: {
                                HStack {
                                    Text(product.displayName)
                                    Spacer()
                                    Text(product.displayPrice)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(entitlementService.isPurchasing)
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 16)
                }

                Button("Restore Purchases") {
                    Task {
                        await entitlementService.restorePurchases()
                        if entitlementService.isEntitled { dismiss() }
                    }
                }
                .font(.footnote)
                .disabled(entitlementService.isPurchasing)
                .padding(.top, 4)

                if let errorMessage = entitlementService.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                SubscriptionLegalFooter()
                    .padding(.top, 8)

                Spacer()
            }
            .padding()
            .navigationTitle("Subscribe")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await entitlementService.loadProducts()
            }
    }
}
