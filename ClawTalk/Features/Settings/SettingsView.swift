import SwiftUI

struct SettingsView: View {
    @Bindable var store: SettingsStore
    var gatewayConnection: GatewayConnection
    @Environment(\.dismiss) private var dismiss

    @State private var connectionTestState: ConnectionTestState = .idle
    @State private var elevenLabsVoices: [ElevenLabsVoice] = []
    @State private var voicesFetchState: FetchState = .idle
    @State private var previewService: (any SpeechService)?
    @State private var previewPlayback: AudioPlaybackManager?
    @State private var isPreviewing = false

    enum ConnectionTestState: Equatable {
        case idle
        case testing
        case success
        case failed(String)
    }

    enum FetchState: Equatable {
        case idle
        case loading
        case loaded
        case loadedDefaults
    }

    var body: some View {
        NavigationStack {
            Form {
                connectionSection
                displaySection
                voiceSection
                ttsSection
                sttSection
                dataSection
                securitySection
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                            store.save()
                            dismiss()
                        }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Connection

    private var connectionSection: some View {
        Section {
            TextField("网关 URL", text: $store.settings.gatewayURL)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            SecureField("网关令牌", text: $store.gatewayToken)
                .textContentType(.password)

            Toggle("WebSocket 模式", isOn: $store.settings.useWebSocket)
                .onChange(of: store.settings.useWebSocket) { _, newValue in
                    if newValue {
                        store.settings.showTokenUsage = false
                        // Auto-connect when toggled on
                        if store.isConfigured {
                            store.save()
                            Task {
                                await gatewayConnection.connect(
                                    resolvedURL: store.settings.resolvedWebSocketURL,
                                    token: store.gatewayToken
                                )
                            }
                        }
                    } else {
                        // Disconnect when toggled off
                        Task {
                            await gatewayConnection.disconnect()
                        }
                    }
                }

            if store.settings.useWebSocket {
                HStack {
                    Text("WS 端口或路径")
                    Spacer()
                    TextField("/ws", text: $store.settings.webSocketPath)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                }
            }

            if store.settings.useWebSocket {
                // Live WebSocket connection status
                HStack {
                    Text("连接")
                    Spacer()
                    switch gatewayConnection.connectionState {
                    case .connected:
                        HStack(spacing: 6) {
                            Circle()
                                .fill(.green)
                                .frame(width: 8, height: 8)
                            Text("已连接")
                                .font(.subheadline)
                                .foregroundStyle(.green)
                        }
                    case .connecting:
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("连接中...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    case .disconnected:
                        HStack(spacing: 6) {
                            Circle()
                                .fill(.red)
                                .frame(width: 8, height: 8)
                            Text("已断开")
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        }
                    }
                }

                if gatewayConnection.connectionState == .disconnected {
                    if let error = gatewayConnection.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button("重新连接") {
                        store.save()
                        Task {
                            await gatewayConnection.connect(
                                resolvedURL: store.settings.resolvedWebSocketURL,
                                token: store.gatewayToken
                            )
                        }
                    }
                    .disabled(store.settings.gatewayURL.isEmpty || store.gatewayToken.isEmpty)
                }
            } else {
                // HTTP connection test
                Button(action: { testConnection() }) {
                    HStack {
                        Text("测试连接")
                        Spacer()
                        switch connectionTestState {
                        case .idle:
                            EmptyView()
                        case .testing:
                            ProgressView()
                                .scaleEffect(0.8)
                        case .success:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .failed:
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
                .disabled(store.settings.gatewayURL.isEmpty || store.gatewayToken.isEmpty || connectionTestState == .testing)

                if case .failed(let error) = connectionTestState {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        } header: {
            Text("IronClaw 服务")
        } footer: {
            if store.settings.useWebSocket {
                Text("WebSocket 仅保留给现有局域网/网关能力。聊天主链路使用 IronClaw 的线程接口：/api/chat/thread/new、/api/chat/send 与 /api/chat/history。")
            } else {
                Text("使用 IronClaw 原生线程接口，并通过 thread id 续接会话。")
            }
        }
    }

    // MARK: - Display

    private var displaySection: some View {
        Section {
            Toggle("显示令牌用量", isOn: $store.settings.showTokenUsage)
                .disabled(store.settings.useWebSocket)
        } header: {
            Text("显示")
        } footer: {
            if store.settings.useWebSocket {
                Text("WebSocket 模式下不支持令牌用量。关闭 WebSocket 以查看令牌计数。")
            } else {
                Text("在助手消息下方显示输入/输出令牌计数。需要 IronClaw 返回线程级用量数据。")
            }
        }
    }

    // MARK: - Voice Toggle

    private var voiceSection: some View {
        Section {
            Toggle("语音输入 (STT)", isOn: $store.settings.voiceInputEnabled)
            Toggle("语音输出 (TTS)", isOn: $store.settings.voiceOutputEnabled)
            Toggle("触觉反馈", isOn: $store.settings.hapticsEnabled)
        } header: {
            Text("语音")
        } footer: {
            Text("关闭语音可使用纯文字聊天。语音输入使用设备端转录。触觉反馈在对话按钮和消息事件上提供触感反馈。")
        }
    }

    // MARK: - TTS Provider

    private var ttsSection: some View {
        Section {
            Picker("提供商", selection: $store.settings.ttsProvider) {
                ForEach(TTSProvider.allCases) { provider in
                    Text(provider.rawValue).tag(provider)
                }
            }

            switch store.settings.ttsProvider {
            case .elevenlabs:
                SecureField("API 密钥", text: $store.elevenLabsAPIKey)
                    .textContentType(.password)
                    .onChange(of: store.elevenLabsAPIKey) { oldValue, newValue in
                        guard oldValue != newValue else { return }
                        // Reset voices when key changes so user re-fetches
                        elevenLabsVoices = []
                        voicesFetchState = .idle
                    }

                if elevenLabsVoices.isEmpty {
                    Button(action: { fetchElevenLabsVoices() }) {
                        HStack {
                            Text("加载声音")
                            Spacer()
                            if voicesFetchState == .loading {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                    }
                    .disabled(store.elevenLabsAPIKey.isEmpty || voicesFetchState == .loading)
                } else {
                    Picker("声音", selection: $store.settings.elevenLabsVoiceID) {
                        ForEach(elevenLabsVoices) { voice in
                            Text(voice.name).tag(voice.voice_id)
                        }
                    }
                }

                if voicesFetchState == .loadedDefaults {
                    Text("显示默认声音。在 API 密钥上启用 \"voices_read\" 可查看所有声音，包括自定义声音。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                voicePreviewButton
            case .openai:
                SecureField("API 密钥", text: $store.openAIAPIKey)
                    .textContentType(.password)
                Picker("声音", selection: $store.settings.openAIVoice) {
                    Text("Alloy").tag("alloy")
                    Text("Echo").tag("echo")
                    Text("Fable").tag("fable")
                    Text("Onyx").tag("onyx")
                    Text("Nova").tag("nova")
                    Text("Shimmer").tag("shimmer")
                }

                voicePreviewButton
            case .apple:
                voicePreviewButton
            }
        } header: {
            Text("文字转语音")
        } footer: {
            switch store.settings.ttsProvider {
            case .elevenlabs:
                Text("ElevenLabs 提供最自然的声音。\n免费套餐: 每月 10,000 个字符。")
            case .openai:
                Text("OpenAI TTS 性价比高，质量良好。")
            case .apple:
                Text("Apple 内置声音。免费且支持离线，但不太自然。")
            }
        }
        .onAppear {
            if store.settings.ttsProvider == .elevenlabs && !store.elevenLabsAPIKey.isEmpty && elevenLabsVoices.isEmpty {
                fetchElevenLabsVoices()
            }
        }
    }

    // MARK: - STT Model

    @State private var pendingModelSize: WhisperModelSize?
    @State private var showModelConfirm = false

    private var sttSection: some View {
        Section {
            Picker("Whisper 模型", selection: Binding(
                get: { store.settings.whisperModelSize },
                set: { newSize in
                    if newSize == .largeTurbo && store.settings.whisperModelSize != .largeTurbo {
                        pendingModelSize = newSize
                        showModelConfirm = true
                    } else {
                        store.settings.whisperModelSize = newSize
                    }
                }
            )) {
                ForEach(WhisperModelSize.allCases) { model in
                    Text(model.displayName).tag(model)
                }
            }
            .confirmationDialog("下载大型模型？", isPresented: $showModelConfirm, titleVisibility: .visible) {
                Button("下载 (~1.6 GB)") {
                    if let size = pendingModelSize {
                        store.settings.whisperModelSize = size
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("Large Turbo 模型提供最佳准确度，但需要约 1.6 GB 存储空间。将在下次语音输入时下载。")
            }
        } header: {
            Text("语音转文字")
        } footer: {
            Text("完全在设备端运行。音频不会离开您的手机。")
        }
    }

    // MARK: - Security Info

    // MARK: - Data

    @State private var showClearConfirm = false

    private var dataSection: some View {
        Section {
            Button("清除聊天记录", role: .destructive) {
                showClearConfirm = true
            }
            .confirmationDialog("清除所有聊天记录？", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("清除记录", role: .destructive) {
                    ConversationStore.shared.clearAll()
                }
            } message: {
                Text("此操作无法撤销。")
            }
        } header: {
            Text("数据")
        } footer: {
            Text("聊天记录存储在本设备上，使用 iOS 数据保护（静态加密）。")
        }
    }

    // MARK: - Connection Test

    private func testConnection() {
        // Save current values before testing
        store.save()
        connectionTestState = .testing

        Task {
            do {
                let baseURL = store.settings.gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                guard let url = URL(string: "\(baseURL)/v1/models") else {
                    connectionTestState = .failed("IronClaw URL 无效")
                    return
                }

                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.setValue("Bearer \(store.gatewayToken)", forHTTPHeaderField: "Authorization")
                request.timeoutInterval = 15

                let (_, response) = try await URLSession.shared.data(for: request)

                if let http = response as? HTTPURLResponse {
                    switch http.statusCode {
                    case 200...299:
                        connectionTestState = .success
                    case 401, 403:
                        connectionTestState = .failed("认证失败 (HTTP \(http.statusCode))。请检查 IronClaw 令牌。")
                    default:
                        connectionTestState = .failed("IronClaw 返回 HTTP \(http.statusCode)")
                    }
                } else {
                    connectionTestState = .failed("意外的响应")
                }
            } catch let error as URLError {
                switch error.code {
                case .notConnectedToInternet:
                    connectionTestState = .failed("无网络连接")
                case .timedOut:
                    connectionTestState = .failed("连接超时。请检查 URL 并确保网关正在运行。")
                case .cannotFindHost, .cannotConnectToHost:
                    connectionTestState = .failed("无法连接到网关。请检查 URL。")
                case .secureConnectionFailed:
                    connectionTestState = .failed("SSL/TLS 连接失败。请确保网关使用 HTTPS。")
                default:
                    connectionTestState = .failed(error.localizedDescription)
                }
            } catch {
                connectionTestState = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - ElevenLabs Voices

    private func voiceLabel(for id: String) -> String {
        if let voice = elevenLabsVoices.first(where: { $0.voice_id == id }) {
            return voice.name
        }
        return id.isEmpty ? "选择声音" : "声音 (\(id.prefix(8))...)"
    }

    private func fetchElevenLabsVoices() {
        let apiKey = store.elevenLabsAPIKey
        guard !apiKey.isEmpty else { return }
        voicesFetchState = .loading
        Task {
            let result = await ElevenLabsVoice.fetchAll(apiKey: apiKey)
            elevenLabsVoices = result.voices
            voicesFetchState = result.usedAPI ? .loaded : .loadedDefaults
        }
    }

    // MARK: - Voice Preview

    private var voicePreviewButton: some View {
        Button(action: { isPreviewing ? stopPreview() : startPreview() }) {
            HStack {
                Text(isPreviewing ? "停止预览" : "预览声音")
                Spacer()
                if isPreviewing {
                    Image(systemName: "stop.circle.fill")
                        .foregroundStyle(.openClawRed)
                } else {
                    Image(systemName: "play.circle.fill")
                        .foregroundStyle(.openClawRed)
                }
            }
        }
        .disabled(previewDisabled)
    }

    private var previewDisabled: Bool {
        switch store.settings.ttsProvider {
        case .elevenlabs:
            return store.elevenLabsAPIKey.isEmpty || store.settings.elevenLabsVoiceID.isEmpty
        case .openai:
            return store.openAIAPIKey.isEmpty
        case .apple:
            return false
        }
    }

    private func startPreview() {
        let sampleText = "你好！这是你选择的声音的预览。"

        let tts: any SpeechService
        switch store.settings.ttsProvider {
        case .elevenlabs:
            tts = ElevenLabsTTSService(voiceID: store.settings.elevenLabsVoiceID, apiKey: store.elevenLabsAPIKey)
        case .openai:
            tts = OpenAITTSService(voice: store.settings.openAIVoice, apiKey: store.openAIAPIKey)
        case .apple:
            tts = AppleTTSService()
        }

        previewService = tts
        isPreviewing = true

        if store.settings.ttsProvider == .apple {
            // Apple TTS plays directly via AVSpeechSynthesizer
            let _ = tts.streamSpeech(text: sampleText)
            // Auto-reset after a delay since Apple TTS doesn't give us completion
            Task {
                try? await Task.sleep(for: .seconds(4))
                if isPreviewing { isPreviewing = false }
            }
        } else {
            // ElevenLabs/OpenAI stream PCM through playback manager
            let playback = AudioPlaybackManager()
            previewPlayback = playback

            Task {
                do {
                    try playback.start()
                    let audioStream = tts.streamSpeech(text: sampleText)
                    for try await chunk in audioStream {
                        playback.enqueue(pcmData: chunk)
                    }
                    playback.markStreamingDone()
                    await playback.waitUntilFinished()
                } catch {
                    // Preview failed silently
                }
                playback.stop()
                isPreviewing = false
                previewPlayback = nil
            }
        }
    }

    private func stopPreview() {
        previewService?.stop()
        previewPlayback?.stop()
        previewPlayback = nil
        previewService = nil
        isPreviewing = false
    }

    // MARK: - Security Info

    private var securitySection: some View {
        Section {
            LabeledContent("令牌存储", value: "iOS 钥匙串")
            LabeledContent("传输方式", value: store.settings.useWebSocket ? "WSS（辅助）+ HTTPS（主链路）" : "仅 HTTPS")
            LabeledContent("STT 处理", value: "设备端")
        } header: {
            Text("安全")
        } footer: {
            Text("API 密钥和令牌存储在 iOS 钥匙串中，静态加密。语音在设备端转录——音频不会离开您的手机。代理通信使用 HTTPS。")
        }
    }
}
