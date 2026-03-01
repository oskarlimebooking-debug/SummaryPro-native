import Foundation

enum STTProvider: String, Codable, CaseIterable, Identifiable {
    case google
    case whisper
    case soniox

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .google: return "Google Speech"
        case .whisper: return "OpenAI Whisper"
        case .soniox: return "Soniox"
        }
    }

    var historyLabel: String {
        switch self {
        case .google: return "Google"
        case .whisper: return "Whisper"
        case .soniox: return "Soniox"
        }
    }
}

enum WhisperModel: String, CaseIterable, Identifiable {
    case whisper1 = "whisper-1"
    case gpt4oTranscribe = "gpt-4o-transcribe"
    case gpt4oMiniTranscribe = "gpt-4o-mini-transcribe"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .whisper1: return "Whisper-1"
        case .gpt4oTranscribe: return "GPT-4o Transcribe"
        case .gpt4oMiniTranscribe: return "GPT-4o Mini Transcribe"
        }
    }
}

enum SupportedLanguage: String, CaseIterable, Identifiable {
    case slovenian = "sl-SI"
    case englishUS = "en-US"
    case englishUK = "en-GB"
    case german = "de-DE"
    case croatian = "hr-HR"
    case serbian = "sr-RS"
    case italian = "it-IT"
    case french = "fr-FR"
    case spanish = "es-ES"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .slovenian: return "Slovenščina"
        case .englishUS: return "English (US)"
        case .englishUK: return "English (UK)"
        case .german: return "Deutsch"
        case .croatian: return "Hrvatski"
        case .serbian: return "Srpski"
        case .italian: return "Italiano"
        case .french: return "Français"
        case .spanish: return "Español"
        }
    }

    var shortCode: String {
        rawValue.components(separatedBy: "-").first ?? rawValue
    }
}
