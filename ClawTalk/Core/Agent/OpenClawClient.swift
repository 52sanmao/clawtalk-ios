import Foundation
import os.log

private let logger = Logger(subsystem: "com.openclaw.clawtalk", category: "network")

final class OpenClawClient {
    private let session: URLSession
    let deviceID: String

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        self.session = URLSession(configuration: config)
        self.deviceID = Self.stableDeviceID()
    }

    // MARK: - Unified Streaming

    /// 兼容现有 UI 的统一流式入口；HTTP 主链路已切换到 IronClaw 线程接口。
    func stream(
        messages: [Message],
        gatewayURL: String,
        token: String,
        model: String = "default",
        apiMode: AgentAPIMode,
        previousResponseId: String? = nil
    ) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        switch apiMode {
        case .chatCompletions, .openResponses:
            return streamThreadResponse(
                messages: messages,
                gatewayURL: gatewayURL,
                token: token,
                model: model,
                requestedThreadID: previousResponseId
            )
        }
    }

    // MARK: - IronClaw Thread API

    private func streamThreadResponse(
        messages: [Message],
        gatewayURL: String,
        token: String,
        model: String,
        requestedThreadID: String? = nil
    ) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    _ = model
                    let threadID = try await resolveThreadID(
                        requestedThreadID: requestedThreadID,
                        gatewayURL: gatewayURL,
                        token: token
                    )
                    let baselineHistory = try await fetchThreadHistory(
                        threadID: threadID,
                        gatewayURL: gatewayURL,
                        token: token
                    )
                    let baselineTurnCount = baselineHistory.turns.count
                    let content = latestOutboundContent(from: messages)

                    guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw OpenClawError.emptyResponse
                    }

                    try await postThreadMessage(
                        content: content,
                        threadID: threadID,
                        gatewayURL: gatewayURL,
                        token: token
                    )

                    let poll = try await waitForThreadTurn(
                        threadID: threadID,
                        afterTurnCount: baselineTurnCount,
                        gatewayURL: gatewayURL,
                        token: token
                    )

                    let reply = (poll.latestTurn.response ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    if !reply.isEmpty {
                        continuation.yield(.textDelta(reply))
                    }

                    continuation.yield(.completed(
                        tokenUsage: tokenUsage(from: poll.latestTurn),
                        responseId: threadID
                    ))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func streamChat(
        messages: [Message],
        gatewayURL: String,
        token: String,
        model: String = "default"
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let eventStream = stream(
                        messages: messages,
                        gatewayURL: gatewayURL,
                        token: token,
                        model: model,
                        apiMode: .openResponses
                    )

                    for try await event in eventStream {
                        if case .textDelta(let content) = event {
                            continuation.yield(content)
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func chat(
        messages: [Message],
        gatewayURL: String,
        token: String
    ) async throws -> String {
        var fullText = ""
        for try await chunk in streamChat(messages: messages, gatewayURL: gatewayURL, token: token) {
            fullText += chunk
        }
        guard !fullText.isEmpty else {
            throw OpenClawError.emptyResponse
        }
        return fullText
    }

    private func resolveThreadID(
        requestedThreadID: String?,
        gatewayURL: String,
        token: String
    ) async throws -> String {
        if let requestedThreadID,
           !requestedThreadID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return requestedThreadID
        }

        return try await createThread(gatewayURL: gatewayURL, token: token).id
    }

    private func createThread(gatewayURL: String, token: String) async throws -> IronClawThreadInfo {
        let url = try endpointURL(gatewayURL: gatewayURL, path: "/api/chat/thread/new")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response, data: data)
        return try JSONDecoder.snakeCase.decode(IronClawThreadInfo.self, from: data)
    }

    private func postThreadMessage(
        content: String,
        threadID: String,
        gatewayURL: String,
        token: String
    ) async throws {
        let url = try endpointURL(gatewayURL: gatewayURL, path: "/api/chat/send")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(IronClawSendRequest(
            content: content,
            threadId: threadID,
            timezone: TimeZone.current.identifier
        ))

        if let size = request.httpBody?.count {
            logger.info("IronClaw thread send body size: \(size) bytes (\(size / 1024)KB)")
        }

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response, data: data)
    }

    private func fetchThreadHistory(
        threadID: String,
        gatewayURL: String,
        token: String
    ) async throws -> IronClawThreadHistoryResponse {
        let encoded = threadID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? threadID
        let url = try endpointURL(gatewayURL: gatewayURL, path: "/api/chat/history?thread_id=\(encoded)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response, data: data)
        return try JSONDecoder.snakeCase.decode(IronClawThreadHistoryResponse.self, from: data)
    }

    private func waitForThreadTurn(
        threadID: String,
        afterTurnCount: Int,
        gatewayURL: String,
        token: String,
        timeout: TimeInterval = 45
    ) async throws -> ThreadPollResult {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            try Task.checkCancellation()
            let history = try await fetchThreadHistory(threadID: threadID, gatewayURL: gatewayURL, token: token)

            if history.turns.count > afterTurnCount,
               let latestTurn = history.turns.last,
               let state = latestTurn.state?.lowercased(),
               isTerminalTurnState(state) {
                if state.contains("failed") {
                    throw OpenClawError.responseError(latestTurn.error ?? "响应失败")
                }
                return ThreadPollResult(history: history, latestTurn: latestTurn)
            }

            try await Task.sleep(nanoseconds: 800_000_000)
        }

        throw OpenClawError.responseError("等待 IronClaw 响应超时")
    }

    private func latestOutboundContent(from messages: [Message]) -> String {
        guard let message = messages.last(where: { $0.role == .user }) else {
            return ""
        }

        var parts: [String] = []
        let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            parts.append(trimmed)
        }
        if let imageData = message.imageData, !imageData.isEmpty {
            let descriptors = imageData.enumerated().map { index, _ in
                "[图片 \(index + 1)]"
            }
            parts.append(descriptors.joined(separator: "\n"))
        }
        return parts.joined(separator: "\n\n")
    }

    private func tokenUsage(from turn: IronClawThreadTurn) -> TokenUsage? {
        if let input = turn.inputTokens,
           let output = turn.outputTokens {
            return TokenUsage(inputTokens: input, outputTokens: output, totalTokens: input + output)
        }
        if let total = turn.totalTokens {
            return TokenUsage(inputTokens: 0, outputTokens: total, totalTokens: total)
        }
        return nil
    }

    private func isTerminalTurnState(_ state: String) -> Bool {
        state.contains("completed") || state.contains("failed") || state.contains("accepted")
    }

    private func endpointURL(gatewayURL: String, path: String) throws -> URL {
        let baseURL = gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw OpenClawError.invalidURL
        }
        try requireSecureConnection(url)
        return url
    }

    private func validateHTTP(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw OpenClawError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data.prefix(500), encoding: .utf8) ?? ""
            throw OpenClawError.httpErrorDetailed(http.statusCode, data.count, body)
        }
    }

    // MARK: - Tool Invocation

    /// Invoke a tool directly via POST /tools/invoke.
    /// Returns the raw result JSON Data for caller to decode into domain types.
    func invokeTool(
        tool: String,
        action: String? = nil,
        args: [String: JSONValue]? = nil,
        sessionKey: String? = nil,
        gatewayURL: String,
        token: String
    ) async throws -> Data {
        let baseURL = gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard let url = URL(string: "\(baseURL)/tools/invoke") else {
            throw OpenClawError.invalidURL
        }

        try requireSecureConnection(url)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let body = ToolInvokeRequest(
            tool: tool,
            action: action,
            args: args,
            sessionKey: sessionKey
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw OpenClawError.invalidResponse
        }

        // Try to parse error body for both HTTP errors and {ok: false} responses
        if !((200...299).contains(http.statusCode)) {
            if http.statusCode == 404 {
                throw OpenClawError.toolError("当前 IronClaw 部署未启用工具接口（/tools/invoke），该功能不可用。")
            }
            if let errorResponse = try? JSONDecoder().decode(ToolInvokeResponse.self, from: data),
               let errorType = errorResponse.error?.type,
               let msg = errorResponse.error?.message {
                if errorType == "not_found" {
                    throw OpenClawError.toolNotFound(tool)
                }
                throw OpenClawError.toolError(msg)
            }
            throw OpenClawError.httpError(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(ToolInvokeResponse.self, from: data)

        guard decoded.ok else {
            let msg = decoded.error?.message ?? "工具调用失败"
            throw OpenClawError.toolError(msg)
        }

        // Re-encode the result value as Data for domain-specific decoding
        guard let result = decoded.result else {
            return Data()
        }
        return try JSONEncoder().encode(result)
    }


    /// Check if a URL is secure enough for API calls.
    /// HTTPS is required for public hosts. HTTP is allowed for local/private network addresses.
    func requireSecureConnection(_ url: URL) throws {
        try Self.validateConnectionSecurity(url)
    }

    /// Static validation for testability. Throws `OpenClawError.insecureConnection` if the URL
    /// is plain HTTP to a non-local/non-private host.
    static func validateConnectionSecurity(_ url: URL) throws {
        if url.scheme == "https" { return }
        guard url.scheme == "http", let host = url.host?.lowercased() else {
            throw OpenClawError.insecureConnection
        }
        // Allow HTTP for local/private network addresses
        if host == "localhost" || host == "127.0.0.1" || host == "::1"
            || host.hasSuffix(".local")
            || host.hasPrefix("192.168.")
            || host.hasPrefix("10.")
            || host.hasPrefix("172.16.") || host.hasPrefix("172.17.") || host.hasPrefix("172.18.")
            || host.hasPrefix("172.19.") || host.hasPrefix("172.2") || host.hasPrefix("172.3")
        {
            return
        }
        throw OpenClawError.insecureConnection
    }

    /// Use the Ed25519 device identity as the stable device ID.
    /// This is the same identity used for WebSocket handshake signing,
    /// ensuring consistent identification across HTTP and WebSocket paths.
    private static func stableDeviceID() -> String {
        let identity = DeviceIdentityManager.loadOrCreate()
        return identity.deviceId
    }
}

enum OpenClawError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case httpErrorDetailed(Int, Int, String)
    case emptyResponse
    case insecureConnection
    case responseError(String)
    case toolError(String)
    case toolNotFound(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "网关 URL 无效。"
        case .invalidResponse: return "服务器响应无效。"
        case .httpError(let code): return "服务器返回 HTTP \(code)。"
        case .httpErrorDetailed(let code, let bodyKB, let resp):
            let respPreview = resp.prefix(200)
            return "HTTP \(code) (已发送 \(bodyKB/1024)KB): \(respPreview)"
        case .emptyResponse: return "代理返回了空响应。"
        case .insecureConnection: return "需要 HTTPS。不允许纯 HTTP 连接。"
        case .responseError(let msg): return msg
        case .toolError(let msg): return msg
        case .toolNotFound(let name): return "工具不可用: \(name)。请检查代理的工具配置。"
        }
    }
}

extension OpenClawClient {
    /// Resolve the best available HTTP token: prefer a cached device auth
    /// token from the gateway (issued during WebSocket handshake), fall back
    /// to the user-provided settings token.
    static func resolveHTTPToken(settingsToken: String, gatewayURL: String) -> String {
        let identity = DeviceIdentityManager.loadOrCreate()
        let host = URL(string: gatewayURL)?.host ?? gatewayURL
        if let entry = DeviceAuthTokenStore.loadToken(
            deviceId: identity.deviceId, role: "operator", gatewayHost: host
        ) {
            return entry.token
        }
        if let entry = DeviceAuthTokenStore.loadToken(
            deviceId: identity.deviceId, role: "user", gatewayHost: host
        ) {
            return entry.token
        }
        return settingsToken
    }
}
