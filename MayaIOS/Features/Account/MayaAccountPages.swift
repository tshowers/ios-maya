import SwiftUI
import TODDAuthKit
import TODDAwardsKit
import TODDProfileKit

/// Every page ChatView pushes - pages with a back button, never sheets.
enum MayaRoute: Hashable {
    case onboarding
    case unlock
    case paywall
    case gettingStarted
    case profile
    case awards
}

enum MayaAccount {
    static let showAtStartupKey = "maya.gettingStarted.showAtStartup"

    static func gettingStartedAPI(authService: AuthService) -> GettingStartedAPI {
        GettingStartedAPI(
            baseURL: AppConfig.fromBundle().apiBaseURL,
            path: "getting-started/maya",
            idToken: { @MainActor [weak authService] in
                guard let authService else { throw AuthServiceError.notSignedIn }
                return try await authService.freshIdToken()
            }
        )
    }

    /// The shared in-app profile screen (TODDProfileKit) - also where the
    /// App Store-required "Delete account" lives.
    @MainActor
    static func profileView(authService: AuthService) -> some View {
        ProfileView(
            api: authService.profileAPI,
            appName: "Maya",
            accent: MayaTheme.accent,
            onAccountDeleted: {
                AuthService.profileStore.clear()
                try? authService.signOut()
            }
        ) {
            MayaTheme.background
        }
    }
}
