import Foundation

/// The three external data providers feeding the app, and how each is ingested.
enum DataSource: String, CaseIterable, Identifiable, Sendable {
    case wyscout
    case statsBomb
    case skillCorner

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .wyscout: "Wyscout"
        case .statsBomb: "StatsBomb"
        case .skillCorner: "SkillCorner"
        }
    }

    var ingestion: String {
        switch self {
        case .wyscout: "CSV import"
        case .statsBomb: "Events · 360"
        case .skillCorner: "Physical"
        }
    }

    var summary: String {
        switch self {
        case .wyscout: "Scouting, player & competition data delivered as CSV exports."
        case .statsBomb: "Granular match events plus 360° freeze-frame context."
        case .skillCorner: "Physical output, sprint and high-intensity tracking data."
        }
    }

    var symbol: String {
        switch self {
        case .wyscout: "tablecells"
        case .statsBomb: "scope"
        case .skillCorner: "figure.run"
        }
    }
}

/// Connection state for a provider, surfaced on the dashboard.
struct DataSourceStatus: Identifiable, Hashable, Sendable {
    let source: DataSource
    var isConnected: Bool
    var lastSyncedAt: Date?

    var id: DataSource { source }
}
