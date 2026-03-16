import Foundation

enum GatewayType: String, Codable, CaseIterable {
    case local
    case cloud
    case custom
}

enum ConnectionStatus: String, Codable {
    case online
    case offline
    case error
}

struct Gateway: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var url: String
    var type: GatewayType
    var status: ConnectionStatus
    var ping: Int?
}
