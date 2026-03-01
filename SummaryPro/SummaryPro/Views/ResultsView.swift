import SwiftUI

struct ResultsView: View {
    @EnvironmentObject var recordingViewModel: RecordingViewModel

    @State private var transcriptCopied = false
    @State private var emailCopied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Raw Transcript
                    transcriptSection

                    // Summaries
                    if let error = recordingViewModel.summaryError {
                        errorCard(message: error)
                    } else {
                        ForEach(Array(recordingViewModel.summaries.enumerated()), id: \.offset) { index, summary in
                            SummaryCardView(summary: summary, index: index)
                        }
                    }

                    // Follow-up Email (meeting mode)
                    if recordingViewModel.isMeetingMode {
                        emailSection
                    }

                    // New Session Button
                    Button(action: {
                        recordingViewModel.newSession()
                    }) {
                        Text("Nov posnetek")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.102, green: 0.451, blue: 0.910))
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Rezultati")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var transcriptSection: some View {
        DisclosureGroup("Surovi prepis") {
            VStack(alignment: .leading, spacing: 8) {
                Text(recordingViewModel.transcript)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Button(action: copyTranscript) {
                    Text(transcriptCopied ? "Kopirano!" : "Kopiraj prepis")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        )
    }

    // MARK: - Follow-up Email Section

    @ViewBuilder
    private var emailSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "envelope.fill")
                    .foregroundStyle(Color(red: 0.102, green: 0.451, blue: 0.910))
                Text("Follow-up email")
                    .font(.headline)

                Spacer()

                Button(action: copyEmail) {
                    Text(emailCopied ? "Kopirano!" : "Kopiraj")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }

            if let error = recordingViewModel.emailError {
                Text("Napaka pri generiranju emaila: \(error)")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            } else if !recordingViewModel.followUpEmail.isEmpty {
                Text(recordingViewModel.followUpEmail)
                    .font(.subheadline)
                    .textSelection(.enabled)
            } else {
                Text("Email ni bil generiran.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        )
    }

    private func errorCard(message: String) -> some View {
        VStack(spacing: 8) {
            Text("Napaka pri povzemanju: \(message)")
                .font(.subheadline)
                .foregroundStyle(.red)
            Text("Prepis je bil shranjen v zgodovino.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        )
    }

    private func copyTranscript() {
        UIPasteboard.general.string = recordingViewModel.transcript
        transcriptCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            transcriptCopied = false
        }
    }

    private func copyEmail() {
        UIPasteboard.general.string = recordingViewModel.followUpEmail
        emailCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            emailCopied = false
        }
    }
}
