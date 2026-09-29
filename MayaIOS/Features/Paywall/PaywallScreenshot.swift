import Foundation

/// Debug-only: launching with `-paywallScreenshot` opens straight to the
/// paywall showing the subscription as App Store Connect lists it, for the
/// subscription's App Review screenshot - which Apple asks for before
/// StoreKit will serve the product, so the real paywall can't show it yet.
/// Always nil in Release builds (TestFlight / App Store).
enum PaywallScreenshot {
    struct Preview {
        let name: String
        let price: String
    }

    static var current: Preview? {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-paywallScreenshot") else { return nil }
        return Preview(name: "TODD Maya", price: "$4.99")
        #else
        return nil
        #endif
    }
}
