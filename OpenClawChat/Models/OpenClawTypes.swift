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
