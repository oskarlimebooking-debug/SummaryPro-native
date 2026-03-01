import Foundation

final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    private let key = "sp_history"
    private let maxEntries = 50

    @Published var entries: [RecordingEntry] = []

    private init() {
        entries = loadFromDisk()
    }

    func save(entry: RecordingEntry) {
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        persist()
    }

    func update(id: String, summary: SummaryData) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].summary = summary
        persist()
    }

    func updateEmail(id: String, email: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].followUpEmail = email
        persist()
    }

    func delete(id: String) {
        entries.removeAll { $0.id == id }
        persist()
    }

    func getAll() -> [RecordingEntry] {
        return entries
    }

    func entry(for id: String) -> RecordingEntry? {
        return entries.first { $0.id == id }
    }

    // MARK: - Persistence

    private func loadFromDisk() -> [RecordingEntry] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([RecordingEntry].self, from: data)) ?? []
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
