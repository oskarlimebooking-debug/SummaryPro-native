import Foundation

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var selectedEntry: RecordingEntry?
    @Published var isRegenerating = false
    @Published var regenerateError: String?
    @Published var isRegeneratingEmail = false
    @Published var regenerateEmailError: String?

    private var historyStore: HistoryStore?
    private var appViewModel: AppViewModel?

    func configure(historyStore: HistoryStore, appViewModel: AppViewModel) {
        self.historyStore = historyStore
        self.appViewModel = appViewModel
    }

    var entries: [RecordingEntry] {
        historyStore?.entries ?? []
    }

    func selectEntry(_ entry: RecordingEntry) {
        selectedEntry = entry
    }

    func deleteEntry(_ id: String) {
        historyStore?.delete(id: id)
        if selectedEntry?.id == id {
            selectedEntry = nil
        }
    }

    func regenerateSummary(entryId: String, model: GeminiModel) async {
        guard let store = historyStore,
              let appVM = appViewModel,
              let entry = store.entry(for: entryId) else { return }

        isRegenerating = true
        regenerateError = nil

        do {
            let summaries = try await GeminiService.summarize(
                model: model,
                transcript: entry.transcript,
                apiKey: appVM.geminiApiKey
            )
            let summaryData = SummaryData(
                model: model.id,
                modelName: model.name,
                summaries: summaries
            )
            store.update(id: entryId, summary: summaryData)

            // Refresh selected entry
            if selectedEntry?.id == entryId {
                selectedEntry = store.entry(for: entryId)
            }
        } catch {
            regenerateError = error.localizedDescription
        }

        isRegenerating = false
    }

    func refineEmail(entryId: String, instructions: String, model: GeminiModel) async {
        guard let store = historyStore,
              let appVM = appViewModel,
              let entry = store.entry(for: entryId),
              let currentEmail = entry.followUpEmail else { return }

        isRegeneratingEmail = true
        regenerateEmailError = nil

        do {
            let refined = try await MeetingEmailService.refineEmail(
                currentEmail: currentEmail,
                instructions: instructions,
                transcript: entry.transcript,
                model: model,
                apiKey: appVM.geminiApiKey
            )
            store.updateEmail(id: entryId, email: refined)

            if selectedEntry?.id == entryId {
                selectedEntry = store.entry(for: entryId)
            }
        } catch {
            regenerateEmailError = error.localizedDescription
        }

        isRegeneratingEmail = false
    }

    func regenerateEmail(entryId: String, model: GeminiModel) async {
        guard let store = historyStore,
              let appVM = appViewModel,
              let entry = store.entry(for: entryId) else { return }

        isRegeneratingEmail = true
        regenerateEmailError = nil

        do {
            let email = try await MeetingEmailService.generateFollowUpEmail(
                model: model,
                transcript: entry.transcript,
                apiKey: appVM.geminiApiKey
            )
            store.updateEmail(id: entryId, email: email)

            // Refresh selected entry
            if selectedEntry?.id == entryId {
                selectedEntry = store.entry(for: entryId)
            }
        } catch {
            regenerateEmailError = error.localizedDescription
        }

        isRegeneratingEmail = false
    }
}
