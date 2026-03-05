import Foundation
import MLX
import MLXLLM
import MLXLMCommon

// MARK: - Model Configuration

let availableModels: [String: String] = [
    // Qwen3 - best for tool calling
    "0.6b": "mlx-community/Qwen3-0.6B-4bit",
    "1.7b": "mlx-community/Qwen3-1.7B-4bit",
    "4b": "mlx-community/Qwen3-4B-4bit",
    // Qwen2.5 - fallback
    "q2-0.5b": "mlx-community/Qwen2.5-0.5B-Instruct-4bit",
    "q2-1.5b": "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
    "q2-7b": "mlx-community/Qwen2.5-7B-Instruct-4bit",
    // DeepSeek R1 - reasoning
    "r1": "mlx-community/DeepSeek-R1-Distill-Qwen-1.5B-4bit",
]

// MARK: - Model Loading with Local Cache

func resolveModelPath(_ modelId: String, forceOnline: Bool) -> ModelConfiguration {
    if forceOnline {
        return ModelConfiguration(id: modelId)
    }
    
    // Check local cache first for faster loading
    let cacheBase = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cache/huggingface/hub")
    let modelDirName = "models--\(modelId.replacingOccurrences(of: "/", with: "--"))"
    let snapshotsDir = cacheBase.appendingPathComponent(modelDirName).appendingPathComponent("snapshots")
    
    if let snapshots = try? FileManager.default.contentsOfDirectory(at: snapshotsDir, includingPropertiesForKeys: nil),
       let snapshot = snapshots.first {
        let configFile = snapshot.appendingPathComponent("config.json")
        if FileManager.default.fileExists(atPath: configFile.path) {
            return ModelConfiguration(directory: snapshot)
        }
    }
    
    return ModelConfiguration(id: modelId)
}
