import SwiftUI

struct HistoryDetailView: View {
    let entry: RecordingEntry

    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var historyViewModel: HistoryViewModel
    @EnvironmentObject var historyStore: HistoryStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedModelId: String = ""
    @State private var showDeleteAlert = false
    @State private var transcriptCopied = false
    @State private var emailCopied = false
    @State private var refinePrompt = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerSection
                transcriptSection
                summarySection
                if currentEntry.isMeetingMode {
                    emailSection
                }
                regenerateSection
                if currentEntry.isMeetingMode {
                    regenerateEmailSection
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(currentEntry.summary?.summaries.first?.title ?? "Posnetek")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Izbriši", role: .destructive) {
                    showDeleteAlert = true
                }
                .foregroundStyle(.red)
            }
        }
        .alert("Izbrisati ta posnetek?", isPresented: $showDeleteAlert) {
            Button("Izbriši", role: .destructive) {
                historyViewModel.deleteEntry(entry.id)
                dismiss()
            }
            Button("Prekliči", role: .cancel) {}
        }
        .onAppear {
            if let model = currentEntry.summary?.model {
                selectedModelId = model
            } else if let first = appViewModel.availableModels.first {
                selectedModelId = first.id
            }
        }
    }

    private var currentEntry: RecordingEntry {
        historyStore.entry(for: entry.id) ?? entry
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(formattedDate(currentEntry.date))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if currentEntry.isMeetingMode {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.caption2)
                        Text("Sestanek")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(red: 0.102, green: 0.451, blue: 0.910).opacity(0.15))
                    )
                    .foregroundStyle(Color(red: 0.102, green: 0.451, blue: 0.910))
                }
            }
            Text("Trajanje: \(currentEntry.duration) · Jezik: \(currentEntry.language)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Transcript

    private var transcriptSection: some View {
        DisclosureGroup("Surovi prepis") {
            VStack(alignment: .leading, spacing: 8) {
                Text(currentEntry.transcript)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Button(action: {
                    UIPasteboard.general.string = currentEntry.transcript
                    transcriptCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        transcriptCopied = false
                    }
                }) {
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

    // MARK: - Summary

    @ViewBuilder
    private var summarySection: some View {
        if historyViewModel.isRegenerating {
            VStack(spacing: 12) {
                ProgressView()
                Text("Generiranje povzetka...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            )
        } else if let error = historyViewModel.regenerateError {
            VStack(spacing: 8) {
                Text("Napaka: \(error)")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            )
        } else if let summary = currentEntry.summary {
            VStack(alignment: .leading, spacing: 12) {
                Text("Model: \(summary.modelName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(Array(summary.summaries.enumerated()), id: \.offset) { index, item in
                    SummaryCardView(summary: item, index: index)
                }
            }
        } else {
            VStack(spacing: 8) {
                Text("Povzetek ni na voljo.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Uporabite gumb spodaj za generiranje.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            )
        }
    }

    // MARK: - Follow-up Email

    @ViewBuilder
    private var emailSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "envelope.fill")
                    .foregroundStyle(Color(red: 0.102, green: 0.451, blue: 0.910))
                Text("Follow-up email")
                    .font(.headline)

                Spacer()

                if currentEntry.followUpEmail != nil {
                    Button(action: copyEmail) {
                        Text(emailCopied ? "Kopirano!" : "Kopiraj")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
            }

            if historyViewModel.isRegeneratingEmail {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Generiranje emaila...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else if let error = historyViewModel.regenerateEmailError {
                Text("Napaka: \(error)")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            } else if let email = currentEntry.followUpEmail, !email.isEmpty {
                HTMLTextView(html: email)
                    .frame(minHeight: 200)
            } else {
                Text("Email ni bil generiran. Uporabite gumb spodaj.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Refine prompt
            if let email = currentEntry.followUpEmail, !email.isEmpty, !historyViewModel.isRegeneratingEmail {
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
                        Button(action: refineCurrentEmail) {
                            Text("Popravi")
                                .font(.subheadline)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.102, green: 0.451, blue: 0.910))
                        .disabled(refinePrompt.trimmingCharacters(in: .whitespaces).isEmpty)
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

    // MARK: - Regenerate Summary

    private var regenerateSection: some View {
        HStack(spacing: 12) {
            Picker("Model", selection: $selectedModelId) {
                ForEach(appViewModel.availableModels) { model in
                    Text(model.name).tag(model.id)
                }
            }
            .pickerStyle(.menu)
            .tint(.primary)

            Button(action: regenerate) {
                Text("Ponovno povzemi")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.102, green: 0.451, blue: 0.910))
            .disabled(historyViewModel.isRegenerating)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        )
    }

    // MARK: - Regenerate Email

    private var regenerateEmailSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "envelope.arrow.triangle.branch")
                .foregroundStyle(Color(red: 0.102, green: 0.451, blue: 0.910))

            Button(action: regenerateEmail) {
                Text("Ponovno generiraj email")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.102, green: 0.451, blue: 0.910))
            .disabled(historyViewModel.isRegeneratingEmail)

            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        )
    }

    // MARK: - Actions

    private func regenerate() {
        guard let model = appViewModel.availableModels.first(where: { $0.id == selectedModelId }) else { return }
        Task {
            await historyViewModel.regenerateSummary(entryId: entry.id, model: model)
        }
    }

    private func regenerateEmail() {
        guard let model = appViewModel.availableModels.first(where: { $0.id == selectedModelId }) else { return }
        Task {
            await historyViewModel.regenerateEmail(entryId: entry.id, model: model)
        }
    }

    private func refineCurrentEmail() {
        guard let model = appViewModel.availableModels.first(where: { $0.id == selectedModelId }) else { return }
        let prompt = refinePrompt
        refinePrompt = ""
        Task {
            await historyViewModel.refineEmail(entryId: entry.id, instructions: prompt, model: model)
        }
    }

    private func copyEmail() {
        guard let email = currentEntry.followUpEmail else { return }
        let pasteboard = UIPasteboard.general
        var items: [[String: Any]] = []
        var item: [String: Any] = [:]
        if let htmlData = email.data(using: .utf8) {
            item["public.html"] = htmlData
        }
        let plain = email.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        item["public.utf8-plain-text"] = plain
        items.append(item)
        pasteboard.items = items
        emailCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            emailCopied = false
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sl_SI")
        formatter.dateFormat = "d. MMMM yyyy 'ob' HH:mm"
        return formatter.string(from: date)
    }
}
