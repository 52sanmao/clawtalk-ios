import Foundation
import OSLog
import UIKit
import UserNotifications

/// Manages a WebSocket connection with role "node", allowing the agent
/// to invoke device capabilities (device info, notifications, etc.).
@Observable
@MainActor
final class NodeConnection {

    enum State: Sendable {
        case disconnected
        case connecting
        case connected
    }

    private(set) var connectionState: State = .disconnected
    private(set) var lastError: String?

    private let logger = Logger(subsystem: "com.openclaw.clawtalk", category: "node-conn")
    private var gateway: GatewayWebSocket?

    // MARK: - Capabilities

    private static let declaredCaps = ["device", "notifications"]
    private static let declaredCommands = [
        "device.status", "device.info",
        "system.notify",
    ]

    // MARK: - Connect

    func connect(resolvedURL: String, token: String) async {
        guard let wsURL = URL(string: resolvedURL) else {
            lastError = "Invalid WebSocket URL"
            return
        }

        if let existing = gateway {
            await existing.shutdown()
        }

        connectionState = .connecting
        lastError = nil
        logger.info("node connecting to \(wsURL.absoluteString, privacy: .public)")

        let gw = GatewayWebSocket(
            url: wsURL,
            token: token,
            role: "node",
            scopes: [],
            caps: Self.declaredCaps,
            commands: Self.declaredCommands,
            clientMode: "node",
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
            connectionState = .connected
            logger.info("node connected")
        } catch {
            logger.error("node connect failed: \(error.localizedDescription, privacy: .public)")
            connectionState = .disconnected
            lastError = error.localizedDescription
        }
    }

    func disconnect() async {
        if let gw = gateway {
            await gw.shutdown()
        }
        gateway = nil
        connectionState = .disconnected
    }

    // MARK: - Event Handling

    private func handlePush(_ push: GatewayWebSocket.Push) async {
        switch push {
        case .snapshot:
            logger.info("node snapshot received")
        case .event(let evt):
            if evt.event == "node.invoke.request" {
                await handleInvokeRequest(evt)
            }
        case .seqGap(let expected, let received):
            logger.warning("node event sequence gap: expected \(expected), got \(received)")
        }
    }

    private func handleStateChange(_ state: GatewayWebSocket.ConnectionState) {
        let newState: State = switch state {
        case .connected: .connected
        case .connecting: .connecting
        case .disconnected: .disconnected
        }
        connectionState = newState
    }

    // MARK: - Invoke Dispatch

    private func handleInvokeRequest(_ evt: EventFrame) async {
        guard let payload = evt.payload,
              let data = try? JSONEncoder().encode(payload),
              let request = try? JSONDecoder().decode(NodeInvokeRequest.self, from: data)
        else {
            logger.error("failed to decode node.invoke.request")
            return
        }

        logger.info("node.invoke: \(request.command, privacy: .public)")

        let result: NodeInvokeResult
        do {
            let response = try await dispatchCommand(request)
            result = NodeInvokeResult(
                id: request.id,
                nodeId: request.nodeId,
                ok: true,
                payloadJSON: response,
                error: nil
            )
        } catch {
            result = NodeInvokeResult(
                id: request.id,
                nodeId: request.nodeId,
                ok: false,
                payloadJSON: nil,
                error: NodeInvokeError(code: "UNAVAILABLE", message: error.localizedDescription)
            )
        }

        // Send result back to gateway
        do {
            guard let gw = gateway else { return }
            let resultData = try JSONEncoder().encode(result)
            let resultCodable = try JSONDecoder().decode(AnyCodable.self, from: resultData)
            let paramsDict = resultCodable.dictValue ?? [:]
            _ = try await gw.request(method: "node.invoke.result", params: paramsDict)
        } catch {
            logger.error("failed to send invoke result: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func dispatchCommand(_ request: NodeInvokeRequest) async throws -> String? {
        switch request.command {
        case "device.info":
            return try encodeJSON(DeviceInfoCapability.getInfo())
        case "device.status":
            return try await encodeJSON(DeviceInfoCapability.getStatus())
        case "system.notify":
            let params = request.decodedParams(as: SystemNotifyParams.self)
            try await NotificationCapability.notify(
                title: params?.title,
                body: params?.body,
                sound: params?.sound,
                priority: params?.priority
            )
            return "{\"ok\":true}"
        default:
            throw NodeError.unknownCommand(request.command)
        }
    }

    private func encodeJSON<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

// MARK: - Protocol Types

struct NodeInvokeRequest: Decodable {
    let id: String
    let nodeId: String
    let command: String
    let paramsJSON: String?
    let timeoutMs: Int?
    let idempotencyKey: String?

    func decodedParams<T: Decodable>(as type: T.Type) -> T? {
        guard let json = paramsJSON, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

struct NodeInvokeResult: Encodable {
    let id: String
    let nodeId: String
    let ok: Bool
    let payloadJSON: String?
    let error: NodeInvokeError?
}

struct NodeInvokeError: Encodable {
    let code: String
    let message: String
}

enum NodeError: LocalizedError {
    case unknownCommand(String)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unknownCommand(let cmd): return "Unknown command: \(cmd)"
        case .unavailable(let msg): return msg
        }
    }
}

// MARK: - System Notify Params

struct SystemNotifyParams: Decodable {
    let title: String?
    let body: String?
    let sound: String?
    let priority: String?
}
