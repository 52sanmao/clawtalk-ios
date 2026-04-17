import Foundation

struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
    let user: String?

    struct ChatMessage: Encodable {
        let role: String
        let content: ChatContent

        enum ChatContent: Encodable {
            case text(String)
            case parts([ContentPart])

            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .text(let string):
                    try container.encode(string)
                case .parts(let parts):
                    try container.encode(parts)
                }
            }
        }

        enum ContentPart: Encodable {
            case text(String)
            case imageURL(String)

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                switch self {
                case .text(let text):
                    try container.encode("text", forKey: .type)
                    try container.encode(text, forKey: .text)
                case .imageURL(let dataURI):
                    try container.encode("image_url", forKey: .type)
                    try container.encode(ImageURL(url: dataURI), forKey: .imageURL)
                }
            }

            private enum CodingKeys: String, CodingKey {
                case type
                case text
                case imageURL = "image_url"
            }

            private struct ImageURL: Encodable {
                let url: String
            }
        }
    }
}

struct ChatCompletionChunk: Decodable {
    let id: String?
    let model: String?
    let choices: [Choice]

    struct Choice: Decodable {
        let delta: Delta?
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    struct Delta: Decodable {
        let content: String?
        let role: String?
    }
}

// MARK: - Shared Types

struct TokenUsage: Codable, Equatable {
    let inputTokens: Int
    let outputTokens: Int
    let totalTokens: Int
}

enum AgentStreamEvent {
    case textDelta(String)
    case modelIdentified(String)
    case completed(tokenUsage: TokenUsage?, responseId: String?)
}

struct IronClawSendRequest: Encodable {
    let content: String
    let threadId: String
    let timezone: String
}

struct IronClawThreadInfo: Decodable {
    let id: String
}

struct IronClawThreadHistoryResponse: Decodable {
    let threadId: String
    let turns: [IronClawThreadTurn]
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case turns
        case hasMore = "has_more"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threadId = try container.decodeIfPresent(String.self, forKey: .threadId) ?? ""
        turns = try container.decodeIfPresent([IronClawThreadTurn].self, forKey: .turns) ?? []
        hasMore = try container.decodeIfPresent(Bool.self, forKey: .hasMore) ?? false
    }
}

struct IronClawThreadTurn: Decodable {
    let turnNumber: Int?
    let userInput: String
    let response: String?
    let state: String
    let startedAt: String?
    let completedAt: String?
    let error: String?
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?

    enum CodingKeys: String, CodingKey {
        case turnNumber = "turn_number"
        case userInput = "user_input"
        case response, state, error
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        turnNumber = try container.decodeIfPresent(Int.self, forKey: .turnNumber)
        userInput = try container.decodeIfPresent(String.self, forKey: .userInput) ?? ""
        response = try container.decodeIfPresent(String.self, forKey: .response)
        state = try container.decodeIfPresent(String.self, forKey: .state) ?? ""
        startedAt = try container.decodeIfPresent(String.self, forKey: .startedAt)
        completedAt = try container.decodeIfPresent(String.self, forKey: .completedAt)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        inputTokens = try container.decodeIfPresent(Int.self, forKey: .inputTokens)
        outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens)
        totalTokens = try container.decodeIfPresent(Int.self, forKey: .totalTokens)
    }
}

struct ThreadPollResult {
    let history: IronClawThreadHistoryResponse
    let latestTurn: IronClawThreadTurn
}

extension JSONDecoder {
    static var snakeCase: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

// MARK: - Models List

struct ModelEntry: Identifiable, Codable, Sendable {
    let id: String
    let name: String?
    let provider: String?
    let contextWindow: Int?
    let reasoning: Bool?

    /// Display label: name if available, otherwise id.
    var displayName: String {
        name ?? id
    }
}

struct ModelsListResponse: Codable, Sendable {
    let models: [ModelEntry]
}

// MARK: - Legacy compatibility response types

struct ChatCompletionResponse: Decodable {
    let id: String
    let choices: [Choice]

    struct Choice: Decodable {
        let message: ResponseMessage
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }

    struct ResponseMessage: Decodable {
        let role: String
        let content: String?
    }
}
