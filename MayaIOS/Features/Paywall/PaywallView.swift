import SwiftUI
import StoreKit
import TODDEntitlementKit

/// Pushed as a page (no popups) from ChatView's "let Maya do the work"
/// banner or a paid action (Download Transcript); Back returns to chat.
/// Unlike the other apps' PaywallView it's dismissible without signing
/// out: advice and personalization are free once signed in (Ty,
/// 2026-09-28) - the subscription unlocks Maya doing the work.
struct PaywallView: View {
    @ObservedObject var entitlementService: EntitlementService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
            VStack(spacing: 16) {
                Spacer()

                Text("Subscribe to Maya")
                    .font(.title2.bold())
                Text("Advice and personalization are free. Subscribe to let Maya do the work: download your conversation transcripts here, and on maya.taliferro.tech create documents, Moves and surveys, decks and status reports.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                if let preview = PaywallScreenshot.current {
                    Button {} label: {
                        HStack {
                            Text(preview.name)
                            Spacer()
                            Text(preview.price)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal, 32)
                    .padding(.top, 16)
                } else if entitlementService.products.isEmpty {
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
