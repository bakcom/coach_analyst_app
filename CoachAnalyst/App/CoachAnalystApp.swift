import SwiftUI

@main
struct CoachAnalystApp: App {
    @State private var auth = AuthStore()
    @State private var scouting = ScoutingStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(scouting)
        }
    }
}
