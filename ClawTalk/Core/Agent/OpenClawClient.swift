import Foundation
import Combine
import os.log

@MainActor
final class ClawTalkLogStore: ObservableObject {
    static let shared = ClawTalkLogStore()

    @Published private(set) var entries: [String] = []
    private let limit = 200

    private init() {}

    func append(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        entries.append("[\(timestamp)] \(message)")
        if entries.count > limit {
            entries.removeFirst(entries.count - limit)
        }
    }

    func clear() {
        entries.removeAll()
    }

    var exportText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "未知"
        let header = [
            "App: 语音爪 / ClawTalk",
            "App 版本: \(version)",
            "Build: \(build)",
            "",
            "日志:",
        ]
        return (header + entries).joined(separator: "\n")
    }
}

private let logger = Logger(subsystem: "com.openclaw.clawtalk", category: "network")

@MainActor
private func appendClawTalkLog(_ message: String) {
    ClawTalkLogStore.shared.append(message)
}

@MainActor
private func appendClawTalkLog(_ prefix: String, error: Error) {
    ClawTalkLogStore.shared.append("\(prefix): \(error.localizedDescription)")
}

struct GatewayValidationResult: Sendable {
    let summary: String
    let details: [String]
    let exportText: String
}

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

    func validateGatewayConnection(
        gatewayURL: String,
        token: String,
        testMessage: String = "ping"
    ) async throws -> GatewayValidationResult {
        await appendClawTalkLog("开始验证聊天主链路：\(gatewayURL)")
        var details: [String] = []

        _ = try await fetchModels(gatewayURL: gatewayURL, token: token)
        details.append("模型接口 /v1/models 可达")
        await appendClawTalkLog("模型接口 /v1/models 可达")

        let thread = try await createThread(gatewayURL: gatewayURL, token: token)
        let trimmedThreadID = thread.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedThreadID.isEmpty else {
            throw OpenClawError.responseError("/api/chat/thread/new 已返回成功，但 thread id 为空")
        }
        details.append("线程创建成功: \(trimmedThreadID)")
        await appendClawTalkLog("线程创建成功: \(trimmedThreadID)")

        let baselineHistory = try await fetchThreadHistory(
            threadID: trimmedThreadID,
            gatewayURL: gatewayURL,
            token: token
        )
        details.append("历史读取成功，当前共有 \(baselineHistory.turns.count) 条 turn")
        await appendClawTalkLog("历史读取成功，当前共有 \(baselineHistory.turns.count) 条 turn")

        try await postThreadMessage(
            content: testMessage,
            threadID: trimmedThreadID,
            gatewayURL: gatewayURL,
            token: token
        )
        details.append("消息发送成功: /api/chat/send")
        await appendClawTalkLog("消息发送成功: /api/chat/send")

        let poll = try await waitForThreadTurn(
            threadID: trimmedThreadID,
            afterTurnCount: baselineHistory.turns.count,
            gatewayURL: gatewayURL,
            token: token,
            timeout: 20
        )

        let reply = (poll.latestTurn.response ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if reply.isEmpty {
            details.append("历史轮询成功，但最新回复为空")
            await appendClawTalkLog("历史轮询成功，但最新回复为空")
        } else {
            details.append("历史轮询成功，已收到回复")
            await appendClawTalkLog("历史轮询成功，已收到回复")
        }

        let exportLines = [
            "IronClaw 地址: \(gatewayURL)",
            "连接验证结果: 聊天主链路可用",
            "检查项:",
        ] + details.map { "- \($0)" }

        return GatewayValidationResult(
            summary: "聊天主链路可用：已完成模型探活、线程创建、发送消息与历史轮询。",
            details: details,
            exportText: exportLines.joined(separator: "\n")
        )
    }

    private func fetchModels(gatewayURL: String, token: String) async throws -> [ModelEntry] {
        await appendClawTalkLog("开始请求 /v1/models")
        await logRequestPreparation(endpoint: "/v1/models", gatewayURL: gatewayURL, token: token)
        let url = try endpointURL(gatewayURL: gatewayURL, path: "/v1/models")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await session.data(for: request)
            try validateHTTP(response, data: data, endpoint: "/v1/models")
            let decoded = try JSONDecoder().decode(ModelsListResponse.self, from: data)
            await appendClawTalkLog("/v1/models 成功，模型数：\(decoded.models.count)")
            return decoded.models
        } catch {
            await appendClawTalkLog("/v1/models 失败", error: error)
            throw error
        }
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
        await appendClawTalkLog("开始创建聊天线程 /api/chat/thread/new")
        await logRequestPreparation(endpoint: "/api/chat/thread/new", gatewayURL: gatewayURL, token: token)
        let url = try endpointURL(gatewayURL: gatewayURL, path: "/api/chat/thread/new")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await session.data(for: request)
            try validateHTTP(response, data: data, endpoint: "/api/chat/thread/new")
            let thread = try JSONDecoder.snakeCase.decode(IronClawThreadInfo.self, from: data)
            await appendClawTalkLog("聊天线程创建成功：\(thread.id)")
            return thread
        } catch {
            await appendClawTalkLog("聊天线程创建失败", error: error)
            throw error
        }
    }

    private func postThreadMessage(
        content: String,
        threadID: String,
        gatewayURL: String,
        token: String
    ) async throws {
        await appendClawTalkLog("开始发送聊天消息 thread=\(threadID) /api/chat/send")
        await logRequestPreparation(endpoint: "/api/chat/send", gatewayURL: gatewayURL, token: token, extra: "thread=\(threadID) chars=\(content.count)")
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

        do {
            let (data, response) = try await session.data(for: request)
            try validateHTTP(response, data: data, endpoint: "/api/chat/send")
            await appendClawTalkLog("聊天消息发送成功 thread=\(threadID)")
        } catch {
            await appendClawTalkLog("聊天消息发送失败 thread=\(threadID)", error: error)
            throw error
        }
    }

    private func fetchThreadHistory(
        threadID: String,
        gatewayURL: String,
        token: String
    ) async throws -> IronClawThreadHistoryResponse {
        await appendClawTalkLog("开始读取聊天历史 thread=\(threadID) /api/chat/history")
        let encoded = threadID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? threadID
        await logRequestPreparation(endpoint: "/api/chat/history", gatewayURL: gatewayURL, token: token, extra: "thread=\(threadID)")
        let url = try endpointURL(gatewayURL: gatewayURL, path: "/api/chat/history?thread_id=\(encoded)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await session.data(for: request)
            try validateHTTP(response, data: data, endpoint: "/api/chat/history")
            do {
                let history = try JSONDecoder.snakeCase.decode(IronClawThreadHistoryResponse.self, from: data)
                await appendClawTalkLog("聊天历史读取成功 thread=\(threadID) turns=\(history.turns.count) hasMore=\(history.hasMore)")
                return history
            } catch {
                let preview = String(data: data.prefix(800), encoding: .utf8) ?? "<non-utf8 body size=\(data.count)>"
                await appendClawTalkLog("聊天历史解码失败 thread=\(threadID) bodyPreview=\(preview)")
                throw OpenClawError.responseError("/api/chat/history 返回 200，但响应结构与客户端预期不一致：\(error.localizedDescription)")
            }
        } catch {
            await appendClawTalkLog("聊天历史读取失败 thread=\(threadID)", error: error)
            throw error
        }
    }

    private func waitForThreadTurn(
        threadID: String,
        afterTurnCount: Int,
        gatewayURL: String,
        token: String,
        timeout: TimeInterval = 45
    ) async throws -> ThreadPollResult {
        let deadline = Date().addingTimeInterval(timeout)
        var attempt = 0

        while Date() < deadline {
            try Task.checkCancellation()
            attempt += 1
            let history = try await fetchThreadHistory(threadID: threadID, gatewayURL: gatewayURL, token: token)
            let latestState = history.turns.last?.state.lowercased() ?? "none"
            await appendClawTalkLog("聊天历史轮询 attempt=\(attempt) thread=\(threadID) baselineTurns=\(afterTurnCount) turns=\(history.turns.count) latest=\(latestState)")

            if history.turns.count > afterTurnCount,
               let latestTurn = history.turns.last {
                let state = latestTurn.state.lowercased()
                if isTerminalTurnState(state) {
                    await appendClawTalkLog("聊天历史轮询命中终态 thread=\(threadID) attempt=\(attempt) state=\(state)")
                    if state.contains("failed") {
                        let message = latestTurn.error ?? latestTurn.response ?? "响应失败"
                        await appendClawTalkLog("聊天历史轮询发现失败终态 thread=\(threadID) message=\(message)")
                        throw OpenClawError.responseError(message)
                    }
                    return ThreadPollResult(history: history, latestTurn: latestTurn)
                }
            }

            try await Task.sleep(nanoseconds: 800_000_000)
        }

        await appendClawTalkLog("聊天历史轮询超时 thread=\(threadID) timeout=\(timeout)")
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
        state.contains("completed") || state.contains("done") || state.contains("failed")
    }

    private func endpointURL(gatewayURL: String, path: String) throws -> URL {
        let normalizedBaseURL = Self.normalizeBaseURL(gatewayURL)
        guard let url = URL(string: "\(normalizedBaseURL)\(path)") else {
            throw OpenClawError.invalidURL
        }
        try requireSecureConnection(url)
        return url
    }

    private static func normalizeBaseURL(_ gatewayURL: String) -> String {
        let trimmed = gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let withScheme: String
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            withScheme = trimmed
        } else {
            withScheme = "https://\(trimmed)"
        }

        guard var components = URLComponents(string: withScheme),
              let scheme = components.scheme?.lowercased(),
              let host = components.host,
              !host.isEmpty else {
            return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }

        components.scheme = scheme
        components.host = host.lowercased()
        components.user = nil
        components.password = nil
        components.path = ""
        components.query = nil
        components.fragment = nil

        var normalized = "\(scheme)://\(host.lowercased())"
        if let port = components.port {
            let defaultPort = scheme == "https" ? 443 : 80
            if port != defaultPort {
                normalized += ":\(port)"
            }
        }
        return normalized.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func logRequestPreparation(endpoint: String, gatewayURL: String, token: String, extra: String? = nil) async {
        let normalizedBaseURL = Self.normalizeBaseURL(gatewayURL)
        let host = URL(string: normalizedBaseURL)?.host ?? normalizedBaseURL
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokenSource = trimmedToken.isEmpty ? "none" : "authorization-header"
        let detailSuffix = extra.map { " \($0)" } ?? ""
        await appendClawTalkLog("准备请求 endpoint=\(endpoint) host=\(host) tokenLoaded=\(!trimmedToken.isEmpty) tokenSource=\(tokenSource)\(detailSuffix)")
    }

    private func detailedHTTPError(data: Data, statusCode: Int, endpoint: String) -> OpenClawError {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty {
            return .responseError("\(endpoint) 失败 (HTTP \(statusCode)): \(message)")
        }

        let bodyPreview = String(data: data.prefix(500), encoding: .utf8) ?? ""
        return .httpErrorDetailed(statusCode, data.count, bodyPreview)
    }

    private func validateHTTP(_ response: URLResponse, data: Data, endpoint: String = "unknown") throws {
        guard let http = response as? HTTPURLResponse else {
            throw OpenClawError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 404, endpoint == "/tools/invoke" {
                throw OpenClawError.toolError("当前 IronClaw 部署未启用工具接口（/tools/invoke），该功能不可用。聊天主链路不受影响。")
            }
            throw detailedHTTPError(data: data, statusCode: http.statusCode, endpoint: endpoint)
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
        let baseURL = Self.normalizeBaseURL(gatewayURL)

        guard let url = URL(string: "\(baseURL)/tools/invoke") else {
            throw OpenClawError.invalidURL
        }

        try requireSecureConnection(url)
        await appendClawTalkLog("开始调用扩展接口 /tools/invoke tool=\(tool) action=\(action ?? "invoke") session=\(sessionKey ?? "none")")
        await logRequestPreparation(endpoint: "/tools/invoke", gatewayURL: gatewayURL, token: token, extra: "tool=\(tool)")

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

        if !((200...299).contains(http.statusCode)) {
            if http.statusCode == 404 {
                await appendClawTalkLog("扩展接口未启用 endpoint=/tools/invoke tool=\(tool) status=404")
                throw OpenClawError.toolError("当前 IronClaw 部署未启用工具接口（/tools/invoke），该功能不可用。聊天主链路不受影响。")
            }
            if let errorResponse = try? JSONDecoder().decode(ToolInvokeResponse.self, from: data),
               let errorType = errorResponse.error?.type,
               let msg = errorResponse.error?.message {
                await appendClawTalkLog("扩展接口调用失败 tool=\(tool) status=\(http.statusCode) type=\(errorType) message=\(msg)")
                if errorType == "not_found" {
                    throw OpenClawError.toolNotFound(tool)
                }
                throw OpenClawError.toolError(msg)
            }
            await appendClawTalkLog("扩展接口调用失败 tool=\(tool) status=\(http.statusCode)")
            throw OpenClawError.httpError(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(ToolInvokeResponse.self, from: data)

        guard decoded.ok else {
            let msg = decoded.error?.message ?? "工具调用失败"
            await appendClawTalkLog("扩展接口返回 ok=false tool=\(tool) message=\(msg)")
            throw OpenClawError.toolError(msg)
        }

        guard let result = decoded.result else {
            await appendClawTalkLog("扩展接口调用成功 tool=\(tool) result=empty")
            return Data()
        }
        await appendClawTalkLog("扩展接口调用成功 tool=\(tool)")
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
