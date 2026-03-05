import SwiftUI

@main
struct OpenClawChatApp: App {
    @State private var settingsStore = SettingsStore()
    @State private var chatViewModel: ChatViewModel?
    @State private var showModelDownload = false
    @State private var modelManager = WhisperModelManager.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if showModelDownload {
                    ModelDownloadView(
                        modelSize: settingsStore.settings.whisperModelSize,
                        onComplete: {
                            showModelDownload = false
                            setup()
                        },
                        onSkip: {
                            showModelDownload = false
                            setup()
                        }
                    )
                } else if let viewModel = chatViewModel {
                    ChatView(viewModel: viewModel, settingsStore: settingsStore)
                } else {
                    ProgressView("Loading...")
                        .onAppear {
                            if !modelManager.hasDownloadedModel && settingsStore.settings.voiceInputEnabled {
                                showModelDownload = true
                            } else {
                                setup()
                            }
                        }
                }
            }
            .preferredColorScheme(.dark)
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
        }
    }

    private func setup() {
        let vm = ChatViewModel(settings: settingsStore)
        configureServices(for: vm)
        chatViewModel = vm
    }

    private func reconfigureServices() {
        guard let vm = chatViewModel else { return }
        configureServices(for: vm)
    }

    private func configureServices(for vm: ChatViewModel) {
        let secure = SecureStorage.shared
        let s = settingsStore.settings

        // STT
        let stt: any TranscriptionService = WhisperKitService(modelSize: s.whisperModelSize)

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
