import SwiftUI

/// Main functionality shell, reached after login.
struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "chart.bar.xaxis") }

            SquadView()
                .tabItem { Label("Squad", systemImage: "person.3.fill") }

            MatchesView()
                .tabItem { Label("Matches", systemImage: "calendar") }

            ScoutView()
                .tabItem { Label("Scouting", systemImage: "magnifyingglass.circle.fill") }

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
    }
}

#Preview {
    MainTabView()
        .environment(AuthStore())
        .environment(ScoutingStore())
}
