import Foundation
import Combine

enum RecordingState {
    case idle
    case recording
    case processing
    case results
    case error(String)
}

enum ProcessingStep {
    case transcribing
    case summarizing
    case generatingEmail
}

@MainActor
final class RecordingViewModel: ObservableObject {
    @Published var state: RecordingState = .idle
    @Published var progress: Double = 0
    @Published var progressMessage: String = ""
    @Published var processingStep: ProcessingStep = .transcribing
    @Published var transcript: String = ""
    @Published var summaries: [Summary] = []
    @Published var summaryError: String?
    @Published var isMeetingMode: Bool = false
    @Published var followUpEmail: String = ""
    @Published var emailError: String?
    @Published var isRefiningEmail: Bool = false

    let audioRecorder = AudioRecorder()
    private var appViewModel: AppViewModel?
    private var historyStore: HistoryStore?
    private var cancellables = Set<AnyCancellable>()

    init() {
        audioRecorder.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
    }

    func configure(appViewModel: AppViewModel, historyStore: HistoryStore) {
        self.appViewModel = appViewModel
        self.historyStore = historyStore
    }

    // MARK: - Recording

    func startRecording() {
        do {
            let started = try audioRecorder.startRecording()
            if started {
                state = .recording
            }
        } catch {
            state = .error("Napaka: ni dostopa do mikrofona")
        }
    }

    func stopRecording() {
        guard case .recording = state else { return }

        guard let result = audioRecorder.stopRecording() else {
            state = .error("Napaka pri ustavitvi snemanja")
            return
        }

        state = .processing
        Task {
            await processRecording(audioURL: result.url, duration: result.duration)
        }
    }

    // MARK: - Processing Pipeline

    private func processRecording(audioURL: URL, duration: String) async {
        guard let appVM = appViewModel else { return }

        processingStep = .transcribing
        progress = 0.1
        progressMessage = "Pretvarjanje zvoka..."

        do {
            // Step 1: Transcribe
            let sttProvider = appVM.selectedSTTProvider
            var transcriptResult: String

            switch sttProvider {
            case .google:
                transcriptResult = try await GoogleSpeechService.transcribe(
                    audioURL: audioURL,
                    language: appVM.selectedLanguage.rawValue,
                    apiKey: appVM.speechApiKey,
                    onProgress: { [weak self] pct, msg in
                        Task { @MainActor in
                            self?.progress = pct
                            self?.progressMessage = msg
                        }
                    }
                )

            case .whisper:
                progress = 0.2
                progressMessage = "Pošiljanje na OpenAI Whisper API..."
                transcriptResult = try await WhisperService.transcribe(
                    audioURL: audioURL,
                    language: appVM.selectedLanguage.rawValue,
                    model: appVM.selectedWhisperModel.rawValue,
                    apiKey: appVM.openaiApiKey,
                    onProgress: { [weak self] pct, msg in
                        Task { @MainActor in
                            self?.progress = pct
                            self?.progressMessage = msg
                        }
                    }
                )

            case .soniox:
                progress = 0.2
                progressMessage = "Pošiljanje na Soniox API..."
                transcriptResult = try await SonioxService.transcribe(
                    audioURL: audioURL,
                    language: appVM.selectedLanguage.rawValue,
                    apiKey: appVM.sonioxApiKey,
                    onProgress: { [weak self] pct, msg in
                        Task { @MainActor in
                            self?.progress = pct
                            self?.progressMessage = msg
                        }
                    }
                )
            }

            if transcriptResult.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                progress = 0
                progressMessage = "V posnetku ni bil zaznan govor."
                try await Task.sleep(nanoseconds: 3_000_000_000)
                state = .idle
                return
            }

            transcript = transcriptResult

            // Step 2: Summarize
            processingStep = .summarizing
            progress = 0.5
            progressMessage = "Pošiljanje na Gemini AI..."

            var summaryData: SummaryData? = nil

            if let model = appVM.selectedGeminiModel {
                do {
                    let resultSummaries = try await GeminiService.summarize(
                        model: model,
                        transcript: transcript,
                        apiKey: appVM.geminiApiKey
                    )
                    summaries = resultSummaries
                    summaryData = SummaryData(
                        model: model.id,
                        modelName: model.name,
                        summaries: resultSummaries
                    )
                    summaryError = nil
                } catch {
                    summaryError = error.localizedDescription
                    summaries = []
                }
            }

            // Step 3: Generate follow-up email (meeting mode only)
            var generatedEmail: String? = nil
            if isMeetingMode, let model = appVM.selectedGeminiModel {
                processingStep = .generatingEmail
                progress = 0.8
                progressMessage = "Generiranje follow-up emaila..."

                do {
                    let email = try await MeetingEmailService.generateFollowUpEmail(
                        model: model,
                        transcript: transcript,
                        apiKey: appVM.geminiApiKey
                    )
                    followUpEmail = email
                    generatedEmail = email
                    emailError = nil
                } catch {
                    emailError = error.localizedDescription
                    followUpEmail = ""
                }
            }

            // Save to history
            let entry = RecordingEntry(
                transcript: transcript,
                language: appVM.selectedLanguage.rawValue,
                duration: duration,
                sttProvider: sttProvider.historyLabel,
                summary: summaryData,
                isMeetingMode: isMeetingMode,
                followUpEmail: generatedEmail
            )
            historyStore?.save(entry: entry)

            state = .results

        } catch {
            progress = 0
            progressMessage = "Napaka: \(error.localizedDescription)"
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            state = .idle
        }

        // Cleanup temp file
        audioRecorder.cleanupTempFile()
    }

    // MARK: - Email Refinement

    func refineEmail(instructions: String) async {
        guard let appVM = appViewModel,
              let model = appVM.selectedGeminiModel,
              !followUpEmail.isEmpty else { return }

        isRefiningEmail = true
        do {
            let refined = try await MeetingEmailService.refineEmail(
                currentEmail: followUpEmail,
                instructions: instructions,
                transcript: transcript,
                model: model,
                apiKey: appVM.geminiApiKey
            )
            followUpEmail = refined
            emailError = nil
        } catch {
            emailError = error.localizedDescription
        }
        isRefiningEmail = false
    }

    // MARK: - Actions

    func newSession() {
        state = .idle
        transcript = ""
        summaries = []
        summaryError = nil
        followUpEmail = ""
        emailError = nil
        progress = 0
        progressMessage = ""
    }
}
