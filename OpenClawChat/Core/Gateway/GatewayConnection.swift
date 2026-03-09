import Foundation
import OSLog

/// High-level gateway connection wrapper over GatewayWebSocket.
/// Provides chat-specific methods and event routing.
@Observable
@MainActor
final class GatewayConnection {

    enum State: Sendable {
        case disconnected
        case connecting
        case connected
    }

    // MARK: - Observable State

    private(set) var connectionState: State = .disconnected
    private(set) var lastError: String?

    // MARK: - Private

    private let logger = Logger(subsystem: "com.openclaw.clawtalk", category: "gateway-conn")
    private var gateway: GatewayWebSocket?
    private var eventContinuations: [UUID: AsyncStream<ChatEventPayload>.Continuation] = [:]

    // MARK: - Connection Lifecycle

    /// Connect to the gateway WebSocket.
    func connect(gatewayURL: String, token: String, port: Int = 18789) async {
        // Derive WebSocket URL from gateway HTTPS URL
        guard let wsURL = Self.webSocketURL(from: gatewayURL, port: port) else {
            lastError = "Invalid gateway URL for WebSocket"
            return
        }

        // Shut down existing connection if any
        if let existing = gateway {
            await existing.shutdown()
        }

        connectionState = .connecting
        lastError = nil

        let gw = GatewayWebSocket(
            url: wsURL,
            token: token,
            pushHandler: { [weak self] push in
                await self?.handlePush(push)
            },
            stateHandler: { [weak self] state in
                await self?.handleStateChange(state)
            }
        )
        gateway = gw

        do {
            try await gw.connect()
        } catch {
            lastError = error.localizedDescription
            logger.error("gateway connect failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Disconnect from the gateway.
    func disconnect() async {
        if let gw = gateway {
            await gw.shutdown()
        }
        gateway = nil
        connectionState = .disconnected
    }

    // MARK: - Chat

    /// Send a chat message via WebSocket. Returns the runId for tracking events.
    func chatSend(
        sessionKey: String,
        message: String,
        idempotencyKey: String = UUID().uuidString,
        timeoutMs: Int = 30000
    ) async throws -> ChatSendResponse {
        guard let gw = gateway else { throw GatewayWebSocket.GatewayError.notConnected }

        let params: [String: AnyCodable] = [
            "sessionKey": AnyCodable(sessionKey),
            "message": AnyCodable(message),
            "thinking": AnyCodable(""),
            "idempotencyKey": AnyCodable(idempotencyKey),
            "timeoutMs": AnyCodable(timeoutMs),
        ]

        return try await gw.requestDecoded(
            method: "chat.send",
            params: params,
            timeoutMs: Double(timeoutMs)
        )
    }

    /// Fetch chat history from the server.
    func chatHistory(sessionKey: String, limit: Int? = nil) async throws -> ChatHistoryPayload {
        guard let gw = gateway else { throw GatewayWebSocket.GatewayError.notConnected }

        var params: [String: AnyCodable] = ["sessionKey": AnyCodable(sessionKey)]
        if let limit { params["limit"] = AnyCodable(limit) }

        return try await gw.requestDecoded(method: "chat.history", params: params)
    }

    /// Abort an in-progress chat run.
    func chatAbort(sessionKey: String, runId: String) async throws -> Bool {
        guard let gw = gateway else { throw GatewayWebSocket.GatewayError.notConnected }

        struct AbortResponse: Decodable { let ok: Bool?; let aborted: Bool? }
        let res: AbortResponse = try await gw.requestDecoded(
            method: "chat.abort",
            params: [
                "sessionKey": AnyCodable(sessionKey),
                "runId": AnyCodable(runId),
            ]
        )
        return res.aborted ?? false
    }

    /// Subscribe to chat events. Returns an AsyncStream that yields ChatEventPayload.
    /// Call this BEFORE chatSend to ensure no events are missed.
    func subscribeChatEvents() -> (id: UUID, stream: AsyncStream<ChatEventPayload>) {
        let id = UUID()
        let stream = AsyncStream<ChatEventPayload> { continuation in
            self.eventContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.eventContinuations.removeValue(forKey: id)
                }
            }
        }
        return (id, stream)
    }

    /// Unsubscribe from chat events.
    func unsubscribeChatEvents(id: UUID) {
        eventContinuations[id]?.finish()
        eventContinuations.removeValue(forKey: id)
    }

    // MARK: - RPC Convenience

    /// Make a raw RPC request.
    func request(method: String, params: [String: AnyCodable]? = nil) async throws -> Data {
        guard let gw = gateway else { throw GatewayWebSocket.GatewayError.notConnected }
        return try await gw.request(method: method, params: params)
    }

    // MARK: - Event Handling

    private func handlePush(_ push: GatewayWebSocket.Push) async {
        switch push {
        case .snapshot(let hello):
            logger.info("gateway snapshot received (uptime: \(hello.snapshot.uptimems)ms)")
        case .event(let evt):
            if evt.event == "chat" {
                decodeChatEvent(evt)
            }
        case .seqGap(let expected, let received):
            logger.warning("event sequence gap: expected \(expected), got \(received)")
        }
    }

    private func decodeChatEvent(_ evt: EventFrame) {
        guard let payload = evt.payload else { return }

        // Encode AnyCodable back to JSON, then decode to typed struct
        guard let data = try? JSONEncoder().encode(payload),
              let chatEvent = try? JSONDecoder().decode(ChatEventPayload.self, from: data)
        else { return }

        for (_, continuation) in eventContinuations {
            continuation.yield(chatEvent)
        }
    }

    private nonisolated func handleStateChange(_ state: GatewayWebSocket.ConnectionState) async {
        await MainActor.run {
            switch state {
            case .connected: self.connectionState = .connected
            case .connecting: self.connectionState = .connecting
            case .disconnected: self.connectionState = .disconnected
            }
        }
    }

    // MARK: - URL Helpers

    /// Convert HTTPS gateway URL to WebSocket URL.
    static func webSocketURL(from gatewayURL: String, port: Int = 18789) -> URL? {
        let trimmed = gatewayURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var components = URLComponents(string: trimmed) else { return nil }

        components.scheme = "wss"
        components.port = port
        components.path = ""

        return components.url
    }
}

// MARK: - Chat Event Types

struct ChatSendResponse: Codable, Sendable {
    let runId: String
    let status: String
}

struct ChatEventPayload: Codable, Sendable {
    let runId: String?
    let sessionKey: String?
    let state: String?     // "delta", "final", "error"
    let message: ChatEventMessage?
    let errorMessage: String?
    let stopReason: String?
}

struct ChatEventMessage: Codable, Sendable {
    let role: String?
    let content: [ChatEventContent]?
    let timestamp: Int?
}

struct ChatEventContent: Codable, Sendable {
    let type: String?
    let text: String?
}

struct ChatHistoryPayload: Codable, Sendable {
    let sessionKey: String?
    let sessionId: String?
    let messages: [ChatHistoryMessage]?
    let thinkingLevel: String?
}

struct ChatHistoryMessage: Codable, Sendable {
    let role: String?
    let content: AnyCodable?  // Can be string or array of content parts
    let timestamp: Int?
}
