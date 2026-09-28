import SwiftUI
import TODDAuthKit

/// Presented as a sheet from `ChatView` rather than a full-screen gate —
/// Maya's chat already works signed out, this just unlocks the
/// personalized/persisted version. Sign in with Apple or Google — no
/// password, no email link — via the shared `TODDAuthKit` package.
struct SignInView: View {
    var onSignedIn: (() -> Void)?
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("Connect Maya to TODD")
                .font(.title2.bold())
            Text("Sign in with your TODD account so Maya can see your business context and remember this conversation.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                SignInWithAppleButtonView(
                    onSignedIn: {
                        errorMessage = ""
                        onSignedIn?()
                    },
                    onError: { errorMessage = $0.localizedDescription }
                )
                SignInWithGoogleButtonView(
                    onSignedIn: {
                        errorMessage = ""
                        onSignedIn?()
                    },
                    onError: { errorMessage = $0.localizedDescription }
                )
            }
            .padding(.horizontal, 32)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()
            Spacer()
        }
        .padding()
    }
}
