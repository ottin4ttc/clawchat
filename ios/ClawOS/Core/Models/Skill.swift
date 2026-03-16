import Foundation

struct Skill: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var description: String
    var isEnabled: Bool
}
