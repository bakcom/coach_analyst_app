import Foundation

/// The authenticated coach using the app.
struct User: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let email: String
    let role: String
    let teamID: Team.ID?
}
