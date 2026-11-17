import Foundation

struct Team: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let shortName: String
    /// SF Symbol used as a placeholder crest in the prototype.
    let crestSymbol: String

    init(id: String, name: String, shortName: String, crestSymbol: String = "shield.fill") {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.crestSymbol = crestSymbol
    }
}
