import Foundation
import Combine

@MainActor
final class AppViewModel: ObservableObject {
    @Published var isSetupComplete = false
    @Published var showSetup = false

    @Published var speechApiKey = ""
    @Published var geminiApiKey = ""
    @Published var openaiApiKey = ""
    @Published var sonioxApiKey = ""

    @Published var selectedLanguage: SupportedLanguage = .slovenian
    @Published var selectedSTTProvider: STTProvider = .google
    @Published var selectedWhisperModel: WhisperModel = .whisper1
    @Published var selectedGeminiModel: GeminiModel?
    @Published var availableModels: [GeminiModel] = []
    @Published var isLoadingModels = false

    private let languageKey = "sp_language"
    private let sttProviderKey = "sp_stt_provider"
    private let whisperModelKey = "sp_whisper_model"
    private let selectedModelKey = "sp_selected_model"

    init() {
        loadKeys()
        loadPreferences()
    }

    // MARK: - Keys

    func loadKeys() {
        speechApiKey = KeychainService.get(key: KeychainService.speechKeyId) ?? ""
        geminiApiKey = KeychainService.get(key: KeychainService.geminiKeyId) ?? ""
        openaiApiKey = KeychainService.get(key: KeychainService.openaiKeyId) ?? ""
        sonioxApiKey = KeychainService.get(key: KeychainService.sonioxKeyId) ?? ""

        let hasAnySttKey = !speechApiKey.isEmpty || !openaiApiKey.isEmpty || !sonioxApiKey.isEmpty
        isSetupComplete = hasAnySttKey && !geminiApiKey.isEmpty
    }

    func saveKeys(speech: String, openai: String, soniox: String, gemini: String) {
        if !speech.isEmpty {
            KeychainService.save(key: KeychainService.speechKeyId, value: speech)
            speechApiKey = speech
        }
        if !openai.isEmpty {
            KeychainService.save(key: KeychainService.openaiKeyId, value: openai)
            openaiApiKey = openai
        }
        if !soniox.isEmpty {
            KeychainService.save(key: KeychainService.sonioxKeyId, value: soniox)
            sonioxApiKey = soniox
        }
        if !gemini.isEmpty {
            KeychainService.save(key: KeychainService.geminiKeyId, value: gemini)
            geminiApiKey = gemini
        }

        // Auto-select STT provider based on available keys
        if speech.isEmpty && !openai.isEmpty && soniox.isEmpty {
            selectedSTTProvider = .whisper
            UserDefaults.standard.set(STTProvider.whisper.rawValue, forKey: sttProviderKey)
        } else if speech.isEmpty && openai.isEmpty && !soniox.isEmpty {
            selectedSTTProvider = .soniox
            UserDefaults.standard.set(STTProvider.soniox.rawValue, forKey: sttProviderKey)
        }

        let hasAnySttKey = !speechApiKey.isEmpty || !openaiApiKey.isEmpty || !sonioxApiKey.isEmpty
        isSetupComplete = hasAnySttKey && !geminiApiKey.isEmpty
        showSetup = false

        if isSetupComplete {
            Task { await fetchModels() }
        }
    }

    func resetKeys() {
        KeychainService.deleteAll()
        speechApiKey = ""
        geminiApiKey = ""
        openaiApiKey = ""
        sonioxApiKey = ""
        isSetupComplete = false
        showSetup = true
        availableModels = []
        selectedGeminiModel = nil
    }

    // MARK: - Preferences

    private func loadPreferences() {
        if let lang = UserDefaults.standard.string(forKey: languageKey),
           let language = SupportedLanguage(rawValue: lang) {
            selectedLanguage = language
        }

        if let stt = UserDefaults.standard.string(forKey: sttProviderKey),
           let provider = STTProvider(rawValue: stt) {
            selectedSTTProvider = provider
        }

        if let wm = UserDefaults.standard.string(forKey: whisperModelKey),
           let model = WhisperModel(rawValue: wm) {
            selectedWhisperModel = model
        }
    }

    func setLanguage(_ language: SupportedLanguage) {
        selectedLanguage = language
        UserDefaults.standard.set(language.rawValue, forKey: languageKey)
    }

    func setSTTProvider(_ provider: STTProvider) {
        selectedSTTProvider = provider
        UserDefaults.standard.set(provider.rawValue, forKey: sttProviderKey)
    }

    func setWhisperModel(_ model: WhisperModel) {
        selectedWhisperModel = model
        UserDefaults.standard.set(model.rawValue, forKey: whisperModelKey)
    }

    func setGeminiModel(_ model: GeminiModel) {
        selectedGeminiModel = model
        UserDefaults.standard.set(model.id, forKey: selectedModelKey)
    }

    // MARK: - Models

    func fetchModels() async {
        guard !geminiApiKey.isEmpty else { return }
        isLoadingModels = true

        do {
            let models = try await GeminiService.fetchModels(apiKey: geminiApiKey)
            availableModels = models

            // Restore saved selection or default to first
            let savedId = UserDefaults.standard.string(forKey: selectedModelKey)
            if let savedId, let saved = models.first(where: { $0.id == savedId }) {
                selectedGeminiModel = saved
            } else {
                selectedGeminiModel = models.first
                if let first = models.first {
                    UserDefaults.standard.set(first.id, forKey: selectedModelKey)
                }
            }
        } catch {
            if availableModels.isEmpty {
                availableModels = GeminiModel.fallbackModels
                selectedGeminiModel = availableModels.first
            }
            print("Error fetching models: \(error)")
        }

        isLoadingModels = false
    }

    var currentApiKeyForSTT: String {
        switch selectedSTTProvider {
        case .google: return speechApiKey
        case .whisper: return openaiApiKey
        case .soniox: return sonioxApiKey
        }
    }
}
