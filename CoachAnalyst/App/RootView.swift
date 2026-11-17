import SwiftUI

/// Top-level router. Shows the login screen until the coach is authenticated,
/// then hands off to the main functionality.
struct RootView: View {
    @Environment(AuthStore.self) private var auth

    var body: some View {
        Group {
            if auth.isAuthenticated {
                MainTabView()
                    .transition(.opacity)
            } else {
                LoginView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: auth.isAuthenticated)
    }
}

#Preview {
    RootView()
        .environment(AuthStore())
        .environment(ScoutingStore())
}
