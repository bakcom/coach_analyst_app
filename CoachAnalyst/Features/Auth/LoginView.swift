import SwiftUI

/// Login is the entry point of the app. On success `AuthStore` flips to the
/// signed-in state and `RootView` swaps in the main tab experience.
struct LoginView: View {
    @Environment(AuthStore.self) private var auth

    var body: some View {
        @Bindable var auth = auth

        ZStack {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.9), Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: 60)

                    VStack(spacing: 12) {
                        Image(systemName: "soccerball")
                            .font(.system(size: 56, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Coach Analyst")
                            .font(.largeTitle.bold())
                            .foregroundStyle(.white)
                        Text("Match, player and physical analytics in one place.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 16) {
                        TextField("Email", text: $auth.email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        SecureField("Password", text: $auth.password)
                            .textContentType(.password)

                        if let error = auth.errorMessage {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            auth.signIn()
                        } label: {
                            Group {
                                if auth.isBusy {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Sign In").fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.black)
                        .disabled(auth.isBusy)
                    }
                    .textFieldStyle(.roundedBorder)
                    .padding(20)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))

                    Text("Prototype build · any credentials sign in")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
            }
        }
    }
}

#Preview {
    LoginView().environment(AuthStore())
}
