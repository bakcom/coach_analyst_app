import SwiftUI

/// Registers every push-navigation destination used across the scouting and
/// analysis flows, so tabs and previews share one declaration instead of
/// repeating `navigationDestination` in each screen.
extension View {
    func scoutingDestinations() -> some View {
        self
            .navigationDestination(for: Competition.self) { ScoutTeamsView(competition: $0) }
            .navigationDestination(for: ScoutTeamRoute.self) { ScoutPlayersView(route: $0) }
            .navigationDestination(for: PlayerMetricProfile.self) { ScoutPlayerDetailView(profile: $0) }
            .navigationDestination(for: ScoutComparisonRoute.self) {
                ScoutComparisonView(target: $0.target, candidate: $0.candidate)
            }
            .navigationDestination(for: TeamAnalysisRoute.self) {
                TeamAnalysisView(competition: $0.competition, team: $0.team)
            }
            .navigationDestination(for: MatchRoute.self) { PostGameAnalysisView(route: $0) }
    }
}
