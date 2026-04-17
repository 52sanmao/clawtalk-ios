import Foundation
import SwiftUI

private enum ClawTalkDefaults {
    static let gatewayURL = "https://rare-lark.agent4.near.ai/"
    static let gatewayToken = "b5af51dc17344eab80981e47f5ab5784a0f1df4846e7229fba421ae97021aa1e"
}

@Observable
final class SettingsStore {
    private let defaults = UserDefaults.standard
    private let settingsKey = "app_settings"
    private let secure = SecureStorage.shared

    var settings: AppSettings = .defaults

    var gatewayToken: String = "" {
        didSet { secure.gatewayToken = gatewayToken.isEmpty ? nil : gatewayToken }
    }

    var elevenLabsAPIKey: String = "" {
        didSet { secure.elevenLabsAPIKey = elevenLabsAPIKey.isEmpty ? nil : elevenLabsAPIKey }
    }

    var openAIAPIKey: String = "" {
        didSet { secure.openAIAPIKey = openAIAPIKey.isEmpty ? nil : openAIAPIKey }
    }

    var isConfigured: Bool {
        !settings.gatewayURL.isEmpty && !gatewayToken.isEmpty
    }

    var hasCompletedOnboarding: Bool = false {
        didSet { defaults.set(hasCompletedOnboarding, forKey: "has_completed_onboarding") }
    }

    init() {
        if let data = defaults.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = decoded
        }
        self.gatewayToken = secure.gatewayToken ?? ""
        self.elevenLabsAPIKey = secure.elevenLabsAPIKey ?? ""
        self.openAIAPIKey = secure.openAIAPIKey ?? ""
        self.hasCompletedOnboarding = defaults.bool(forKey: "has_completed_onboarding")

        if settings.gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            settings.gatewayURL = ClawTalkDefaults.gatewayURL
        }
        if gatewayToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            gatewayToken = ClawTalkDefaults.gatewayToken
        }

        // Auto-skip onboarding for existing configured users
        if isConfigured && !hasCompletedOnboarding {
            hasCompletedOnboarding = true
        }
    }

    var optionalWebSocketURL: String? {
        let resolved = settings.resolvedWebSocketURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolved.isEmpty else { return nil }
        return resolved
    }

    func logOptionalWebSocketIntent(context: String) {
        let enabled = settings.useWebSocket
        let resolved = optionalWebSocketURL ?? "未配置"
        ClawTalkLogStore.shared.append("可选 WebSocket 检查 context=\(context) enabled=\(enabled) resolved=\(resolved)")
        if !enabled {
            ClawTalkLogStore.shared.append("可选 WebSocket 已关闭；聊天主链路继续使用 HTTPS 线程接口。")
        }
    }

    func applyGatewayDefaultsIfNeeded() {
        if settings.gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            settings.gatewayURL = ClawTalkDefaults.gatewayURL
        }
        if gatewayToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            gatewayToken = ClawTalkDefaults.gatewayToken
        }
    }

    func connectOptionalWebSocketIfNeeded(gatewayConnection: GatewayConnection, context: String) {
        logOptionalWebSocketIntent(context: context)
        guard settings.useWebSocket else { return }
        guard isConfigured else {
            ClawTalkLogStore.shared.append("跳过可选 WebSocket：缺少 URL 或 Token。")
            return
        }
        guard let resolvedURL = optionalWebSocketURL else {
            ClawTalkLogStore.shared.append("跳过可选 WebSocket：无法解析 WebSocket 地址。")
            return
        }

        Task {
            if gatewayConnection.connectionState == .disconnected {
                await gatewayConnection.connect(resolvedURL: resolvedURL, token: gatewayToken)
            } else {
                ClawTalkLogStore.shared.append("可选 WebSocket 已存在连接，无需重复连接。")
            }
        }
    }

    func connectOptionalWebSocketsIfNeeded(gatewayConnection: GatewayConnection, nodeConnection: NodeConnection, context: String) {
        logOptionalWebSocketIntent(context: context)
        guard settings.useWebSocket else { return }
        guard isConfigured else {
            ClawTalkLogStore.shared.append("跳过可选 WebSocket / Node 通道：缺少 URL 或 Token。")
            return
        }
        guard let resolvedURL = optionalWebSocketURL else {
            ClawTalkLogStore.shared.append("跳过可选 WebSocket / Node 通道：无法解析 WebSocket 地址。")
            return
        }

        Task {
            if gatewayConnection.connectionState == .disconnected {
                await gatewayConnection.connect(resolvedURL: resolvedURL, token: gatewayToken)
            } else {
                ClawTalkLogStore.shared.append("可选 operator WebSocket 已连接或正在连接。")
            }

            if nodeConnection.connectionState == .disconnected {
                await nodeConnection.connect(resolvedURL: resolvedURL, token: gatewayToken)
            } else {
                ClawTalkLogStore.shared.append("可选 node WebSocket 已连接或正在连接。")
            }
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: settingsKey)
        }
    }
}
