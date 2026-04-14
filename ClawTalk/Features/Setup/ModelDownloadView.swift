import SwiftUI

struct ModelDownloadView: View {
    let modelSize: WhisperModelSize
    let onComplete: () -> Void
    let onSkip: () -> Void

    @State private var manager = WhisperModelManager.shared

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 56))
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
                Text(modelSize.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if manager.isDownloading {
                    ProgressView(value: manager.downloadProgress)
                        .tint(.openClawRed)
                        .padding(.horizontal, 32)
                        .padding(.top, 8)
                    Text("下载中... \(Int(manager.downloadProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let error = manager.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
            .padding(.top, 8)

            Spacer()

            VStack(spacing: 12) {
                if manager.isDownloading {
                    // Show cancel-like skip while downloading
                    Button("跳过语音功能") {
                        onSkip()
                    }
                    .foregroundStyle(.secondary)
                } else {
                    Button(action: {
                        Task {
                            await manager.downloadModel(size: modelSize)
                            if manager.isModelReady {
                                onComplete()
                            }
                        }
                    }) {
                        Text("下载模型")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.openClawRed)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.horizontal, 24)

                    Button("暂时跳过") {
                        onSkip()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 32)
        }
        .background(Color(.systemBackground))
    }
}
