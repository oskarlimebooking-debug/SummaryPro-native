import SwiftUI

struct RecordingView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var recordingViewModel: RecordingViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    settingsBar
                    meetingModeToggle
                    whisperModelPicker
                    geminiModelPicker
                    recorderSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Summary Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Spremeni ključe") {
                        appViewModel.showSetup = true
                    }
                    .font(.caption)
                }
            }
        }
    }

    // MARK: - Meeting Mode Toggle

    private var meetingModeToggle: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Način sestanka")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Povzetek + follow-up email")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: $recordingViewModel.isMeetingMode)
                .labelsHidden()
                .tint(Color(red: 0.102, green: 0.451, blue: 0.910))
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        )
    }

    // MARK: - Settings Bar

    private var settingsBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Jezik snemanja")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Jezik", selection: Binding(
                        get: { appViewModel.selectedLanguage },
                        set: { appViewModel.setLanguage($0) }
                    )) {
                        ForEach(SupportedLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.primary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("STT ponudnik")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("STT", selection: Binding(
                        get: { appViewModel.selectedSTTProvider },
                        set: { appViewModel.setSTTProvider($0) }
                    )) {
                        ForEach(STTProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.primary)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        )
    }

    // MARK: - Whisper Model

    @ViewBuilder
    private var whisperModelPicker: some View {
        if appViewModel.selectedSTTProvider == .whisper {
            VStack(alignment: .leading, spacing: 6) {
                Text("Whisper model")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Whisper model", selection: Binding(
                    get: { appViewModel.selectedWhisperModel },
                    set: { appViewModel.setWhisperModel($0) }
                )) {
                    ForEach(WhisperModel.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            )
        }
    }

    // MARK: - Gemini Model

    private var geminiModelPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("AI model")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: {
                    Task { await appViewModel.fetchModels() }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .disabled(appViewModel.isLoadingModels)
            }

            if appViewModel.isLoadingModels {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Nalaganje modelov...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Picker("Model", selection: Binding(
                    get: { appViewModel.selectedGeminiModel?.id ?? "" },
                    set: { newId in
                        if let model = appViewModel.availableModels.first(where: { $0.id == newId }) {
                            appViewModel.setGeminiModel(model)
                        }
                    }
                )) {
                    ForEach(appViewModel.availableModels) { model in
                        Text(model.name).tag(model.id)
                    }
                }
                .pickerStyle(.menu)
                .tint(.primary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        )
    }

    // MARK: - Recorder

    private var recorderSection: some View {
        VStack(spacing: 20) {
            // Background recording indicator
            if recordingViewModel.audioRecorder.isBackgroundRecording {
                HStack(spacing: 6) {
                    Image(systemName: "moon.fill")
                        .foregroundStyle(.orange)
                    Text("Snemanje v ozadju aktivno")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange.opacity(0.12))
                )
            }

            // Visualizer
            AudioVisualizerView(levels: recordingViewModel.audioRecorder.audioLevels)
                .frame(height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            // Timer
            Text(recordingViewModel.audioRecorder.formattedTime)
                .font(.system(size: 48, weight: .light, design: .monospaced))
                .foregroundStyle(isRecording ? .red : .primary)

            // Meeting mode indicator during recording
            if isRecording && recordingViewModel.isMeetingMode {
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill")
                        .foregroundStyle(Color(red: 0.102, green: 0.451, blue: 0.910))
                    Text("Način sestanka")
                        .font(.caption)
                        .foregroundStyle(Color(red: 0.102, green: 0.451, blue: 0.910))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(red: 0.102, green: 0.451, blue: 0.910).opacity(0.12))
                )
            }

            // Controls
            HStack(spacing: 32) {
                Button(action: {
                    recordingViewModel.startRecording()
                }) {
                    Text("Snemaj")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 120, height: 48)
                        .background(isRecording ? Color.red.opacity(0.5) : Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                }
                .disabled(isRecording)
                .opacity(isRecording ? 0.6 : 1.0)

                Button(action: {
                    recordingViewModel.stopRecording()
                }) {
                    Text("Pošlji")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 120, height: 48)
                        .background(isRecording ? Color(red: 0.102, green: 0.451, blue: 0.910) : Color.gray)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                }
                .disabled(!isRecording)
                .opacity(isRecording ? 1.0 : 0.6)
            }

            // Status
            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        )
    }

    private var isRecording: Bool {
        if case .recording = recordingViewModel.state { return true }
        return false
    }

    private var statusText: String {
        switch recordingViewModel.state {
        case .recording: return "Snemanje..."
        case .error(let msg): return msg
        default: return "Pripravljeno"
        }
    }
}
