import SwiftUI

struct ResultsView: View {
    @EnvironmentObject var recordingViewModel: RecordingViewModel

    @State private var transcriptCopied = false
    @State private var emailCopied = false
    @State private var refinePrompt = ""

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

                if !recordingViewModel.followUpEmail.isEmpty {
                    Button(action: copyEmail) {
                        Text(emailCopied ? "Kopirano!" : "Kopiraj")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let error = recordingViewModel.emailError {
                Text("Napaka pri generiranju emaila: \(error)")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            } else if !recordingViewModel.followUpEmail.isEmpty {
                HTMLTextView(html: recordingViewModel.followUpEmail)
                    .frame(minHeight: 200)
            } else {
                Text("Email ni bil generiran.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Refine prompt
            if !recordingViewModel.followUpEmail.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Popravi email")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    TextField("Navodila za popravek...", text: $refinePrompt, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...5)

                    HStack {
                        Spacer()
                        Button(action: {
                            let prompt = refinePrompt
                            refinePrompt = ""
                            Task {
                                await recordingViewModel.refineEmail(instructions: prompt)
                            }
                        }) {
                            HStack(spacing: 4) {
                                if recordingViewModel.isRefiningEmail {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                }
                                Text(recordingViewModel.isRefiningEmail ? "Popravljam..." : "Popravi")
                                    .font(.subheadline)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.102, green: 0.451, blue: 0.910))
                        .disabled(refinePrompt.trimmingCharacters(in: .whitespaces).isEmpty || recordingViewModel.isRefiningEmail)
                    }
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
        copyHTMLToClipboard(recordingViewModel.followUpEmail)
        emailCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            emailCopied = false
        }
    }

    private func copyHTMLToClipboard(_ html: String) {
        let pasteboard = UIPasteboard.general
        var items: [[String: Any]] = []
        var item: [String: Any] = [:]
        if let htmlData = html.data(using: .utf8) {
            item["public.html"] = htmlData
        }
        // Also add plain text fallback (strip HTML tags)
        let plain = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        item["public.utf8-plain-text"] = plain
        items.append(item)
        pasteboard.items = items
    }
}
