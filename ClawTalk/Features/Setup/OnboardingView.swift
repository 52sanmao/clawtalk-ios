import SwiftUI

struct OnboardingView: View {
    @Bindable var settingsStore: SettingsStore
    let onComplete: () -> Void

    @State private var step: Step = .welcome
    @State private var gatewayURL = ClawTalkDefaults.gatewayURL
    @State private var gatewayToken = ClawTalkDefaults.gatewayToken
    @State private var connectionState: ConnectionTestState = .idle
    @State private var connectionDetails: [String] = []
    @State private var connectionExportText = ""
    @State private var showConnectionDetails = false
    @State private var modelManager = WhisperModelManager.shared

    enum Step: Int, CaseIterable {
        case welcome = 0
        case gatewaySetup
        case gateway
        case voice
    }

    enum ConnectionTestState: Equatable {
        case idle
        case testing
        case success(String)
        case failed(String)
    }

    var body: some View {
        TabView(selection: $step) {
            welcomeStep.tag(Step.welcome)
            gatewaySetupStep.tag(Step.gatewaySetup)
            gatewayStep.tag(Step.gateway)
            voiceStep.tag(Step.voice)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .onAppear {
            UIPageControl.appearance().currentPageIndicatorTintColor = UIColor(.openClawRed)
            UIPageControl.appearance().pageIndicatorTintColor = UIColor(.openClawRed).withAlphaComponent(0.3)
        }
        .background(Color(.systemBackground))
        .preferredColorScheme(.dark)
        .onAppear {
            settingsStore.applyGatewayDefaultsIfNeeded()
            gatewayURL = settingsStore.settings.gatewayURL
            gatewayToken = settingsStore.gatewayToken
        }
    }

    // MARK: - Welcome

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image("LogoRed")
                .resizable()
                .scaledToFit()
                .frame(width: 160, height: 160)

            Text("欢迎使用语音爪")
                .font(.title)
                .fontWeight(.bold)

            Text("与您的 OpenClaw AI 代理\n进行语音和文字聊天。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            primaryButton("开始使用") {
                withAnimation { step = .gatewaySetup }
            }
            .padding(.bottom, 80)
        }
    }

    // MARK: - Gateway Setup Instructions

    private var gatewaySetupStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "server.rack")
                .font(.system(size: 48))
                .foregroundStyle(.openClawRed)

            Text("需要网关")
                .font(.title2)
                .fontWeight(.bold)

            Text("语音爪连接到您的计算机或服务器上运行的 OpenClaw 网关。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(alignment: .leading, spacing: 12) {
                bulletPoint("在您的机器上安装 OpenClaw")
                bulletPoint("运行 openclaw onboard 进行配置")
                bulletPoint("在网关配置中启用 HTTP API")
                bulletPoint("设置网关认证令牌")
                bulletPoint("通过 HTTPS 暴露以进行远程访问")
            }
            .padding(.horizontal, 32)

            Link(destination: URL(string: "https://docs.openclaw.ai/gateway")!) {
                HStack(spacing: 6) {
                    Image(systemName: "book.fill")
                    Text("查看设置指南")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.openClawRed)
            }
            .padding(.top, 4)

            Spacer()

            primaryButton("我已有网关") {
                withAnimation { step = .gateway }
            }

            Button("稍后再设置") {
                withAnimation { step = .voice }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.bottom, 60)
        }
    }

    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color.openClawRed)
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Gateway Config

    private var gatewayStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "server.rack")
                .font(.system(size: 48))
                .foregroundStyle(.openClawRed)

            Text("连接到网关")
                .font(.title2)
                .fontWeight(.bold)

            Text("输入您的 OpenClaw 网关 URL 和访问令牌。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("网关 URL")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    TextField("网关 URL", text: $gatewayURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(12)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("网关令牌")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    SecureField("您的访问令牌", text: $gatewayToken)
                        .textContentType(.password)
                        .padding(12)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(.horizontal, 24)

            // Inline connection test result
            if connectionState != .idle {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        switch connectionState {
                        case .testing:
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("测试中...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        case .success(let message):
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(message)
                                .font(.subheadline)
                                .foregroundStyle(.green)
                        case .failed(let error):
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        case .idle:
                            EmptyView()
                        }
                    }

                    if !connectionDetails.isEmpty {
                        Button(showConnectionDetails ? "隐藏诊断详情" : "查看诊断详情") {
                            showConnectionDetails.toggle()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        if showConnectionDetails {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(connectionDetails.enumerated()), id: \.offset) { _, detail in
                                    Text("• \(detail)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }

                        Button("复制诊断文本") {
                            UIPasteboard.general.string = connectionExportText
                        }
                        .font(.caption)
                        .foregroundStyle(.openClawRed)
                    }
                }
                .padding(.horizontal, 24)
                .transition(.opacity)
            }

            Text("连接测试会依次检查 /v1/models、/api/chat/thread/new、/api/chat/send 与 /api/chat/history。通过后表示聊天主链路可用，不等于所有扩展接口都已启用。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)

            Spacer()

            primaryButton(isConnectionSuccess ? "继续" : "测试连接") {
                if isConnectionSuccess {
                    withAnimation { step = .voice }
                } else {
                    settingsStore.settings.gatewayURL = gatewayURL
                    settingsStore.gatewayToken = gatewayToken
                    settingsStore.save()
                    testConnection()
                }
            }
            .disabled(gatewayURL.isEmpty || gatewayToken.isEmpty || connectionState == .testing)
            .opacity(gatewayURL.isEmpty || gatewayToken.isEmpty ? 0.5 : 1)

            Button("跳过") {
                settingsStore.settings.gatewayURL = gatewayURL
                settingsStore.gatewayToken = gatewayToken
                settingsStore.save()
                withAnimation { step = .voice }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.bottom, 60)
        }
        .animation(.easeInOut(duration: 0.2), value: connectionState)
    }

    // MARK: - Voice Setup

    private var voiceStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 48))
                .foregroundStyle(.openClawRed)

            Text("语音设置")
                .font(.title2)
                .fontWeight(.bold)

            Text("语音爪使用设备端语音模型进行私密语音转录。音频不会离开您的手机。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(spacing: 8) {
                Text(settingsStore.settings.whisperModelSize.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if modelManager.isDownloading {
                    ProgressView(value: modelManager.downloadProgress)
                        .tint(.openClawRed)
                        .padding(.horizontal, 32)
                        .padding(.top, 8)
                    Text("下载中... \(Int(modelManager.downloadProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let error = modelManager.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
            .padding(.top, 8)

            Spacer()

            if modelManager.isDownloading {
                Button("跳过语音功能") {
                    finishOnboarding()
                }
                .foregroundStyle(.secondary)
                .padding(.bottom, 60)
            } else if modelManager.hasDownloadedModel {
                primaryButton("完成") {
                    finishOnboarding()
                }
                .padding(.bottom, 60)
            } else {
                primaryButton("下载模型") {
                    Task {
                        await modelManager.downloadModel(size: settingsStore.settings.whisperModelSize)
                        if modelManager.isModelReady {
                            finishOnboarding()
                        }
                    }
                }

                Button("跳过语音设置") {
                    settingsStore.settings.voiceInputEnabled = false
                    settingsStore.save()
                    finishOnboarding()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 60)
            }
        }
        .onAppear {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }

    private var isConnectionSuccess: Bool {
        if case .success = connectionState {
            return true
        }
        return false
    }

    // MARK: - Helpers

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.openClawRed)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.horizontal, 24)
    }

    private func testConnection() {
        connectionState = .testing
        connectionDetails = []
        connectionExportText = ""
        showConnectionDetails = false

        Task {
            let client = OpenClawClient()
            do {
                let result = try await client.validateGatewayConnection(
                    gatewayURL: gatewayURL,
                    token: gatewayToken,
                    testMessage: "Hello from ClawTalk setup"
                )
                connectionDetails = result.details
                connectionExportText = result.exportText
                connectionState = .success(result.summary)
            } catch let error as URLError {
                switch error.code {
                case .notConnectedToInternet:
                    connectionState = .failed("无网络连接")
                case .timedOut:
                    connectionState = .failed("聊天主链路验证超时。请检查 URL、令牌与网关状态。")
                case .cannotFindHost, .cannotConnectToHost:
                    connectionState = .failed("无法连接到网关。请检查 URL。")
                case .secureConnectionFailed:
                    connectionState = .failed("SSL/TLS 失败。请使用 HTTPS。")
                default:
                    connectionState = .failed(error.localizedDescription)
                }
            } catch {
                connectionState = .failed(error.localizedDescription)
            }
        }
    }

    private func finishOnboarding() {
        settingsStore.hasCompletedOnboarding = true
        settingsStore.save()
        onComplete()
    }
}
