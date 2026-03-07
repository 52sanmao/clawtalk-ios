import Foundation

struct Channel: Identifiable, Codable {
    let id: UUID
    var name: String
    var agentId: String
    var systemEmoji: String
    let createdAt: Date

    init(name: String, agentId: String, systemEmoji: String = "🤖") {
        self.id = UUID()
        self.name = name
        self.agentId = agentId
        self.systemEmoji = systemEmoji
        self.createdAt = Date()
    }

    /// The model string to send to the OpenClaw gateway.
    var modelString: String {
        "openclaw:\(agentId)"
    }

    static let `default` = Channel(name: "Main", agentId: "main", systemEmoji: "🦞")
}
