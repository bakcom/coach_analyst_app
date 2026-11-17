import Observation
import SwiftUI

/// Holds authentication state and drives routing between the login screen and
/// the main application.
///
/// Prototype stub: any non-empty email/password signs in. Real auth (Sign in
/// with Apple / OAuth to the BFF) replaces `signIn()` without touching the UI.
@MainActor
@Observable
final class AuthStore {
    enum State: Equatable {
        case signedOut
        case signedIn(User)
    }

    var state: State = .signedOut
    var email = ""
    var password = ""
    var isBusy = false
    var errorMessage: String?

    var isAuthenticated: Bool {
        if case .signedIn = state { return true }
        return false
    }

    var currentUser: User? {
        if case .signedIn(let user) = state { return user }
        return nil
    }

    func signIn() {
        errorMessage = nil
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !password.isEmpty else {
            errorMessage = "Enter your email and password to continue."
            return
        }
        isBusy = true
        defer { isBusy = false }

        let user = User(
            id: "coach-1",
            name: "Alex Morgan",
            email: trimmed,
            role: "Head Coach",
            teamID: nil
        )
        state = .signedIn(user)
    }

    func signOut() {
        state = .signedOut
        email = ""
        password = ""
        errorMessage = nil
    }
}
