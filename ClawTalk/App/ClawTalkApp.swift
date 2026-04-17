import SwiftUI
import UIKit

@main
struct ClawTalkApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var settingsStore: SettingsStore
    @State private var channelStore: ChannelStore
    @State private var selectedChannel: Channel?
    @State private var chatViewModel: ChatViewModel?
    @State private var showModelDownload = false
    @State private var modelManager = WhisperModelManager.shared
    @State private var cachedSTT: WhisperKitService?
    @State private var cachedSTTModelSize: WhisperModelSize?
    @State private var gatewayConnection = GatewayConnection()
    @State private var nodeConnection = NodeConnection()
    @StateObject private var logStore = ClawTalkLogStore.shared
    @State private var showLogViewer = false
    @State private var showCopyAlert = false

    init() {
        #if DEBUG
        DemoDataSeeder.seedIfNeeded()
        #endif
        _settingsStore = State(initialValue: SettingsStore())
        _channelStore = State(initialValue: ChannelStore())
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !settingsStore.hasCompletedOnboarding {
                    OnboardingView(settingsStore: settingsStore) {
                        // Onboarding complete
                    }
                } else if showModelDownload {
                    ModelDownloadView(
                        modelSize: settingsStore.settings.whisperModelSize,
                        onComplete: {
                            showModelDownload = false
                        },
                        onSkip: {
                            showModelDownload = false
                        }
                    )
                } else if let vm = chatViewModel, selectedChannel != nil {
                    ChatView(viewModel: vm, settingsStore: settingsStore, gatewayConnection: gatewayConnection, onBack: goBack, onDeleteChannel: deleteCurrentChannel)
                } else {
                    ChannelListView(
                        channelStore: channelStore,
                        settingsStore: settingsStore,
                        gatewayConnection: gatewayConnection,
                        onSelect: { channel in
                            selectChannel(channel)
                        }
                    )
                    .onAppear {
                        if !modelManager.hasDownloadedModel && settingsStore.settings.voiceInputEnabled {
                            showModelDownload = true
                        }
                    }
                }
            }
            .overlay {
                ApprovalOverlayView(gatewayConnection: gatewayConnection)
            }
            .overlay(alignment: .bottomTrailing) {
                Button {
                    showLogViewer = true
                } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(Color.openClawRed)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 90)
                .accessibilityLabel("查看日志")
            }
            .sheet(isPresented: Binding(
                get: { CanvasCapability.shared.isPresented },
                set: { CanvasCapability.shared.isPresented = $0 }
            )) {
                CanvasView(canvas: CanvasCapability.shared)
            }
            .sheet(isPresented: $showLogViewer) {
                NavigationStack {
                    ScrollView {
                        Text(logStore.exportText)
                            .font(.system(.footnote, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .navigationTitle("语音爪日志")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("关闭") { showLogViewer = false }
                        }
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            Button("清空") {
                                logStore.clear()
                            }
                            Button("复制") {
                                UIPasteboard.general.string = logStore.exportText
                                showCopyAlert = true
                            }
                        }
                    }
                }
            }
            .alert("已复制日志", isPresented: $showCopyAlert) {
                Button("确定", role: .cancel) {}
            } message: {
                Text("复制内容已包含 App 名称和版本。")
            }
            .tint(.openClawRed)
            .onAppear {
                if !settingsStore.hasCompletedOnboarding {
                    ClawTalkLogStore.shared.append("显示新手引导页。")
                }
            }
            .task {
                settingsStore.applyGatewayDefaultsIfNeeded()
                ClawTalkLogStore.shared.append("App 启动完成；聊天主链路使用 HTTPS 线程接口。")
                settingsStore.connectOptionalWebSocketsIfNeeded(
                    gatewayConnection: gatewayConnection,
                    nodeConnection: nodeConnection,
                    context: "app_launch"
                )
            }
            .onChange(of: settingsStore.settings.ttsProvider) {
                reconfigureServices()
            }
            .onChange(of: settingsStore.settings.voiceInputEnabled) {
                reconfigureServices()
            }
            .onChange(of: settingsStore.elevenLabsAPIKey) {
                reconfigureServices()
            }
            .onChange(of: settingsStore.openAIAPIKey) {
                reconfigureServices()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background || newPhase == .inactive {
                    chatViewModel?.saveCurrentState()
                }
            }
        }
    }

    private func selectChannel(_ channel: Channel) {
        let vm = ChatViewModel(
            settings: settingsStore,
            channel: channel,
            channelStore: channelStore,
            gatewayConnection: gatewayConnection
        )
        configureServices(for: vm)
        chatViewModel = vm
        selectedChannel = channel

        // Wire node image injection to chat
        nodeConnection.onImagesReceived = { [weak vm] images, caption in
            vm?.injectImages(images, caption: caption)
        }

        // Optional WebSocket side-channel does not determine HTTP chat usability.
        settingsStore.connectOptionalWebSocketsIfNeeded(
            gatewayConnection: gatewayConnection,
            nodeConnection: nodeConnection,
            context: "select_channel"
        )
        if settingsStore.isConfigured {
            Task {
                vm.loadServerHistory()
            }
        }
    }

    private func goBack() {
        chatViewModel?.stop()
        chatViewModel = nil
        selectedChannel = nil
        nodeConnection.onImagesReceived = nil
    }

    private func deleteCurrentChannel() {
        chatViewModel?.stop()
        if let channel = selectedChannel {
            channelStore.delete(channel)
        }
        chatViewModel = nil
        selectedChannel = nil
    }

    private func reconfigureServices() {
        guard let vm = chatViewModel else { return }
        configureServices(for: vm)
    }

    private func configureServices(for vm: ChatViewModel) {
        let secure = SecureStorage.shared
        let s = settingsStore.settings

        // STT — reuse cached instance if model size hasn't changed
        let stt: any TranscriptionService
        if let cached = cachedSTT, cachedSTTModelSize == s.whisperModelSize {
            stt = cached
        } else {
            let service = WhisperKitService(modelSize: s.whisperModelSize)
            cachedSTT = service
            cachedSTTModelSize = s.whisperModelSize
            stt = service
        }

        // TTS
        let tts: any SpeechService = {
            switch s.ttsProvider {
            case .elevenlabs:
                if let key = secure.elevenLabsAPIKey, !key.isEmpty {
                    return ElevenLabsTTSService(voiceID: s.elevenLabsVoiceID, apiKey: key)
                }
                return AppleTTSService()
            case .openai:
                if let key = secure.openAIAPIKey, !key.isEmpty {
                    return OpenAITTSService(voice: s.openAIVoice, apiKey: key)
                }
                return AppleTTSService()
            case .apple:
                return AppleTTSService()
            }
        }()

        vm.configure(transcription: stt, speech: tts)
    }
}
