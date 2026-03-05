import Foundation
import WhisperKit

@Observable
@MainActor
final class WhisperModelManager {
    static let shared = WhisperModelManager()

    var isDownloading = false
    var downloadProgress: Double = 0
    var isModelReady = false
    var errorMessage: String?

    private let defaults = UserDefaults.standard
    private let downloadedKey = "whisper_model_downloaded"

    var hasDownloadedModel: Bool {
        defaults.bool(forKey: downloadedKey)
    }

    func checkModelAvailable(for size: WhisperModelSize) -> Bool {
        // Check if model files exist locally
        let modelName = size.rawValue
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let modelDir = documentsURL.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-\(modelName)")
        return FileManager.default.fileExists(atPath: modelDir.path)
    }

    func downloadModel(size: WhisperModelSize) async {
        isDownloading = true
        downloadProgress = 0
        errorMessage = nil

        do {
            // WhisperKit downloads the model during initialization
            let config = WhisperKitConfig(
                model: size.rawValue,
                verbose: false,
                prewarm: true
            )
            _ = try await WhisperKit(config)

            isModelReady = true
            isDownloading = false
            downloadProgress = 1.0
            defaults.set(true, forKey: downloadedKey)
        } catch {
            isDownloading = false
            errorMessage = "Download failed: \(error.localizedDescription)"
        }
    }
}
