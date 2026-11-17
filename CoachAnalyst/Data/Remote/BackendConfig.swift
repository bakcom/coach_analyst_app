import Foundation

/// Chooses where scouting data comes from. With no backend URL configured the
/// app computes on-device; a URL switches to the FastAPI BFF.
enum BackendConfig {
    static let defaultsKey = "scoutingBackendURL"
    static let environmentKey = "COACH_BACKEND_URL"

    static var remoteBaseURL: URL? {
        if let value = ProcessInfo.processInfo.environment[environmentKey],
           !value.isEmpty, let url = URL(string: value) {
            return url
        }
        if let value = UserDefaults.standard.string(forKey: defaultsKey),
           !value.isEmpty, let url = URL(string: value) {
            return url
        }
        return nil
    }

    static func makeBackend() -> any ScoutingBackend {
        if let url = remoteBaseURL {
            return RemoteScoutingBackend(baseURL: url)
        }
        return LocalScoutingBackend()
    }
}
