import Foundation

struct GeminiModel: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    var generationConfig: GenerationConfig

    struct GenerationConfig: Codable, Hashable {
        var maxOutputTokens: Int
        var temperature: Double
        var thinkingConfig: ThinkingConfig?
    }

    struct ThinkingConfig: Codable, Hashable {
        var thinkingBudget: Int
    }

    static let fallbackModels: [GeminiModel] = [
        GeminiModel(
            id: "gemini-2.5-flash",
            name: "Gemini 2.5 Flash",
            generationConfig: buildGenConfig(modelId: "gemini-2.5-flash", outputLimit: 8192)
        ),
        GeminiModel(
            id: "gemini-2.5-pro",
            name: "Gemini 2.5 Pro",
            generationConfig: buildGenConfig(modelId: "gemini-2.5-pro", outputLimit: 8192)
        ),
    ]

    static let excludedPatterns = [
        "tts", "image", "embedding", "aqa", "native-audio", "bisheng", "learnlm",
    ]

    static func buildGenConfig(modelId: String, outputLimit: Int) -> GenerationConfig {
        var config = GenerationConfig(
            maxOutputTokens: min(outputLimit, 8192),
            temperature: 0.3,
            thinkingConfig: nil
        )
        if modelId.contains("2.5-pro") || modelId.contains("3-pro") {
            config.thinkingConfig = ThinkingConfig(thinkingBudget: 8000)
        } else if modelId.contains("2.5-flash") && !modelId.contains("lite") {
            config.thinkingConfig = ThinkingConfig(thinkingBudget: 4000)
        }
        return config
    }

    static func sortKey(_ model: GeminiModel) -> Int {
        let id = model.id
        if id == "gemini-2.5-flash" { return 1 }
        if id == "gemini-2.5-pro" { return 2 }
        if id.contains("3-pro") { return 10 }
        if id.contains("3-flash") { return 11 }
        if id.contains("2.5-pro") { return 20 }
        if id.contains("2.5-flash") && !id.contains("lite") { return 21 }
        if id.contains("lite") { return 40 }
        return 50
    }
}
