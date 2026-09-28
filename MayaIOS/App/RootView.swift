import SwiftUI

/// Unlike `pulse-ios`'s `RootView` (which gates the entire app behind
/// sign-in), Maya's chat works signed-out, so this always shows `ChatView`.
struct RootView: View {
    @ObservedObject var authService: AuthService
    @ObservedObject var entitlementService: EntitlementService
    let chatViewModel: ChatViewModel

    var body: some View {
        ChatView(viewModel: chatViewModel, authService: authService, entitlementService: entitlementService)
    }
}
