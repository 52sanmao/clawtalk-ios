import Foundation
import UIKit

@Observable
@MainActor
final class ToolsViewModel {
    // Memory
    var memoryResults: [MemorySearchEntry] = []
    var memoryFileContent: MemoryGetResult?
    var memorySearchQuery = ""

    // Agents
    var agents: [AgentEntry] = []

    // Sessions
    var sessions: [SessionEntry] = []
    var sessionStatus: String?
    var sessionHistory: SessionHistoryResult?

    // Browser
    var browserScreenshot: UIImage?
    var browserStatusText: String?
    var browserTabsText: String?

    // Models
    var availableModels: [ModelEntry] = []
    var isLoadingModels = false

    // Availability
    var toolAvailability: [ToolCategory: Bool] = [:]
    var availabilityChecked = false

    // Common
    var isLoading = false
    var errorMessage: String?

    private let client = OpenClawClient()
    private let settings: SettingsStore
    private let gatewayConnection: GatewayConnection?

    init(settings: SettingsStore, gatewayConnection: GatewayConnection? = nil) {
        self.settings = settings
        self.gatewayConnection = gatewayConnection
    }

    private var gatewayURL: String { settings.settings.gatewayURL }
    private var token: String { settings.gatewayToken }

    enum ToolCategory: String, CaseIterable {
        case memory, agents, sessions, browser, models
    }

    func isAvailable(_ category: ToolCategory) -> Bool {
        if category == .models {
            return settings.isConfigured
        }
        return toolAvailability[category] ?? true
    }

    // MARK: - Availability Check

    func checkAvailability() async {
        guard !availabilityChecked else { return }
        availabilityChecked = true

        let probes: [(ToolCategory, String, String?, [String: JSONValue]?)] = [
            (.memory, "memory_search", nil, ["query": .string("test"), "maxResults": .int(1)]),
            (.agents, "agents_list", nil, nil),
            (.sessions, "sessions_list", nil, ["limit": .int(1)]),
            (.browser, "browser", "status", nil),
        ]

        await withTaskGroup(of: (ToolCategory, Bool).self) { group in
            for (category, tool, action, args) in probes {
                group.addTask { [client, gatewayURL, token] in
                    do {
                        _ = try await client.invokeTool(
                            tool: tool,
                            action: action,
                            args: args,
                            gatewayURL: gatewayURL,
                            token: token
                        )
                        return (category, true)
                    } catch let error as OpenClawError {
                        if case .toolNotFound = error {
                            return (category, false)
                        }
                        // Any other error means the tool exists but something else went wrong
                        return (category, true)
                    } catch {
                        return (category, true)
                    }
                }
            }

            for await (category, available) in group {
                toolAvailability[category] = available
            }
        }
    }

    // MARK: - Memory

    func searchMemory() async {
        let query = memorySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        isLoading = true
        errorMessage = nil

        do {
            let data = try await client.invokeTool(
                tool: "memory_search",
                args: [
                    "query": .string(query),
                    "maxResults": .int(20),
                    "minScore": .double(0.15)
                ],
                gatewayURL: gatewayURL,
                token: token
            )
            // Result is {content, details} — details has the structured data
            let wrapper = try JSONDecoder().decode(ToolResultWrapper<MemorySearchResults>.self, from: data)
            memoryResults = wrapper.details?.results ?? []
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func getMemoryFile(path: String, from: Int? = nil, lines: Int? = nil) async {
        isLoading = true
        errorMessage = nil

        do {
            var args: [String: JSONValue] = ["path": .string(path)]
            if let from { args["from"] = .int(from) }
            if let lines { args["lines"] = .int(lines) }

            let data = try await client.invokeTool(
                tool: "memory_get",
                args: args,
                gatewayURL: gatewayURL,
                token: token
            )
            let wrapper = try JSONDecoder().decode(ToolResultWrapper<MemoryGetResult>.self, from: data)
            memoryFileContent = wrapper.details
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Agents

    func listAgents() async {
        isLoading = true
        errorMessage = nil

        do {
            let data = try await client.invokeTool(
                tool: "agents_list",
                gatewayURL: gatewayURL,
                token: token
            )
            let wrapper = try JSONDecoder().decode(ToolResultWrapper<AgentsListResult>.self, from: data)
            agents = wrapper.details?.agents ?? []
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Sessions

    func listSessions() async {
        isLoading = true
        errorMessage = nil

        do {
            let data = try await client.invokeTool(
                tool: "sessions_list",
                args: ["limit": .int(50)],
                gatewayURL: gatewayURL,
                token: token
            )
            let wrapper = try JSONDecoder().decode(ToolResultWrapper<SessionsListResult>.self, from: data)
            sessions = wrapper.details?.sessions ?? []
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func getSessionStatus(sessionKey: String? = nil) async {
        isLoading = true
        errorMessage = nil

        do {
            var args: [String: JSONValue]?
            if let sessionKey {
                args = ["sessionKey": .string(sessionKey)]
            }

            let data = try await client.invokeTool(
                tool: "session_status",
                args: args,
                gatewayURL: gatewayURL,
                token: token
            )
            // session_status returns text in content and details
            let wrapper = try JSONDecoder().decode(ToolResultWrapper<SessionStatusResult.StatusDetails>.self, from: data)
            sessionStatus = wrapper.details?.statusText
                ?? wrapper.content?.first?.text
                ?? "暂无状态信息"
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func getSessionHistory(sessionKey: String, limit: Int = 20) async {
        isLoading = true
        errorMessage = nil

        do {
            let data = try await client.invokeTool(
                tool: "sessions_history",
                args: [
                    "sessionKey": .string(sessionKey),
                    "limit": .int(limit)
                ],
                gatewayURL: gatewayURL,
                token: token
            )
            let wrapper = try JSONDecoder().decode(ToolResultWrapper<SessionHistoryResult>.self, from: data)
            sessionHistory = wrapper.details
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Browser

    func getBrowserStatus() async {
        isLoading = true
        errorMessage = nil

        do {
            let data = try await client.invokeTool(
                tool: "browser",
                action: "status",
                gatewayURL: gatewayURL,
                token: token
            )
            let wrapper = try JSONDecoder().decode(ToolResultWrapper<BrowserDetails>.self, from: data)
            browserStatusText = wrapper.content?.first?.text ?? "暂无状态"
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func takeBrowserScreenshot() async {
        isLoading = true
        errorMessage = nil

        do {
            let data = try await client.invokeTool(
                tool: "browser",
                action: "screenshot",
                args: ["type": .string("jpeg")],
                gatewayURL: gatewayURL,
                token: token
            )
            let wrapper = try JSONDecoder().decode(ToolResultWrapper<BrowserDetails>.self, from: data)
            if let imageItem = wrapper.content?.first(where: { $0.type == "image" }),
               let base64 = imageItem.image?.data,
               let decoded = Data(base64Encoded: base64) {
                browserScreenshot = UIImage(data: decoded)
            } else if let textContent = wrapper.content?.first?.text,
                      let decoded = Data(base64Encoded: textContent) {
                browserScreenshot = UIImage(data: decoded)
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func getBrowserTabs() async {
        isLoading = true
        errorMessage = nil

        do {
            let data = try await client.invokeTool(
                tool: "browser",
                action: "tabs",
                gatewayURL: gatewayURL,
                token: token
            )
            let wrapper = try JSONDecoder().decode(ToolResultWrapper<BrowserDetails>.self, from: data)
            browserTabsText = wrapper.content?.first?.text ?? "暂无标签页"
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Models

    func loadModels() async {
        guard !isLoadingModels else { return }
        isLoadingModels = true
        errorMessage = nil

        defer { isLoadingModels = false }

        guard settings.isConfigured else {
            errorMessage = "请先在设置中配置 IronClaw 地址与 Token。"
            return
        }

        do {
            let baseURL = gatewayURL
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard let url = URL(string: "\(baseURL)/v1/models") else {
                throw OpenClawError.invalidURL
            }

            try client.requireSecureConnection(url)

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw OpenClawError.invalidResponse
            }
            guard (200...299).contains(http.statusCode) else {
                let body = String(data: data.prefix(500), encoding: .utf8) ?? ""
                throw OpenClawError.httpErrorDetailed(http.statusCode, data.count, body)
            }

            let decoded = try JSONDecoder().decode(IronClawModelsEnvelope.self, from: data)
            availableModels = decoded.data.map {
                ModelEntry(id: $0.id, name: nil, provider: Self.provider(from: $0.id), contextWindow: nil, reasoning: nil)
            }
        } catch {
            errorMessage = "加载模型失败: \(error.localizedDescription)"
        }
    }

    private static func provider(from modelID: String) -> String? {
        let parts = modelID.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return parts[0]
    }
}

private struct IronClawModelsEnvelope: Decodable {
    let data: [IronClawModelEnvelope]
}

private struct IronClawModelEnvelope: Decodable {
    let id: String
}
