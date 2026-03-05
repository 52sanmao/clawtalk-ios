import Foundation

final class ConversationStore {
    static let shared = ConversationStore()

    private let fileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("conversations.json")
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func load() -> [Message] {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let messages = try? decoder.decode([Message].self, from: data) else {
            return []
        }
        // Never restore messages that were mid-stream
        return messages.map { msg in
            var m = msg
            m.isStreaming = false
            return m
        }
    }

    func save(_ messages: [Message]) {
        // Only save completed messages
        let completed = messages.filter { !$0.isStreaming && !$0.content.isEmpty }
        guard let data = try? encoder.encode(completed) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
